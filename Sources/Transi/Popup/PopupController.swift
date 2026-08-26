import AppKit
import SwiftUI

/// Non-activating floating panel: shows the translation near the mouse without
/// stealing focus from the app the user is working in.
final class TranslationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PopupController: ObservableObject {
    // MARK: - Session state

    @Published private(set) var phase: SourcePhase = .capturing
    @Published private(set) var origin: SourceOrigin = .selection
    @Published private(set) var sourceText: String = ""
    /// First detected source language to arrive (first writer wins, so the
    /// header never flickers when a second engine disagrees).
    @Published private(set) var resolvedSourceCode: String?
    @Published var targetCode: String = "fa"
    @Published private(set) var spellingSuggestion: String?
    @Published private(set) var popupError: PopupError?

    // MARK: - Results

    @Published private(set) var cards: [EngineCardState] = []
    @Published private(set) var primaryEngine: EngineID?
    @Published private(set) var sessionHiddenEngines: Set<EngineID> = []
    /// Set briefly after a hide so the footer can offer Undo.
    @Published private(set) var lastHiddenEngine: EngineID?

    // MARK: - Input mode

    @Published var inputDraft: String = ""
    /// Token the view observes to move keyboard focus into the input field; a
    /// fresh UUID re-fires even when focus was already requested once.
    @Published private(set) var focusRequest: UUID?

    // MARK: - Chrome

    @Published var isPinned: Bool = false {
        didSet { refreshMonitors() }
    }
    @Published var isPickerOpen: Bool = false {
        didSet { refreshMonitors() }
    }

    private var panel: TranslationPanel?
    private var clickOutsideMonitor: Any?
    private var escapeMonitor: Any?
    private var globalEscapeMonitor: Any?
    private var resizeObserver: Any?

    private var sessionID = UUID()
    private var streamTask: Task<Void, Never>?
    /// True while the auto-flip decision is deferred to the server's detected
    /// language (ambiguous script). Consumed by the first primary result.
    private var autoFlipPending = false
    private var undoChipTask: Task<Void, Never>?
    private var autoDismissTimer: Timer?
    /// Seconds the pointer has spent continuously outside the dismiss zone.
    private var awayAccumulated: TimeInterval = 0

    private var settings: SettingsStore { SettingsStore.shared }

    // MARK: - Derived

    /// Cards in the user's configured engine order — fixed slots, so every
    /// engine renders its skeleton immediately in its own position and fills
    /// in place when its result lands. Nothing ever reorders on arrival; the
    /// only thing that reorders cards is the user dragging them (or the
    /// Engines tab), which writes the same `engineOrder`.
    var visibleCards: [EngineCardState] {
        let rank = Dictionary(
            uniqueKeysWithValues: settings.engineOrder.enumerated().map { ($1, $0) })
        return cards
            .filter { !sessionHiddenEngines.contains($0.id) }
            .sorted { (rank[$0.id] ?? .max) < (rank[$1.id] ?? .max) }
    }

    /// Popup drag-reorder: move `engine` so it sits where `target` is.
    /// Persists through `SettingsStore.engineOrder`, shared with the Engines
    /// tab's drag list.
    func moveEngine(_ engine: EngineID, before target: EngineID) {
        guard engine != target else { return }
        var order = settings.engineOrder
        guard let from = order.firstIndex(of: engine),
              let to = order.firstIndex(of: target) else { return }
        order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        withAnimation(.easeOut(duration: 0.16)) {
            settings.engineOrder = order
            objectWillChange.send()
        }
    }

    var isTranslating: Bool {
        cards.contains { if case .loading = $0.status { return true } else { return false } }
    }

    /// The card whose text Copy/Speak act on: the reserved primary if it
    /// succeeded, else the top-most successful card — copy always matches
    /// what the user is looking at.
    var primaryCard: EngineCardState? {
        let visible = visibleCards
        if let reserved = reservedPrimary,
           let card = visible.first(where: { $0.id == reserved }), card.status.isSuccess {
            return card
        }
        return visible.first(where: { $0.status.isSuccess })
    }

    var primaryText: String {
        if case .success(let result)? = primaryCard?.status { return result.translatedText }
        return ""
    }

    private var reservedPrimary: EngineID? {
        settings.primaryEngine(forTarget: targetCode)
    }

    var effectiveSourceCode: String? {
        settings.sourceLanguage == LanguageCatalog.autoCode
            ? resolvedSourceCode.map(LanguageCatalog.normalize)
            : settings.sourceLanguage
    }

    var canSpeak: Bool { !primaryText.isEmpty }

    // MARK: - Entry points (called by AppDelegate)

    /// Whether the popup is currently on screen. AppDelegate's double-press
    /// shortcut needs it: pressing the hotkey twice only means "open the
    /// input" when the first press actually produced a popup.
    var isPanelVisible: Bool { panel?.isVisible == true }

    /// Shows the popup the instant the hotkey fires, before the selection has
    /// been read. Deliberately does *not* take key focus: the capture
    /// strategies resolve the selection through the frontmost application, so
    /// stealing focus here would point them at our own panel.
    func showCapturing(near location: NSPoint) {
        beginSession(origin: .selection, phase: .capturing, near: location, takeFocus: false)
    }

    func showTranslating(text: String, near location: NSPoint) {
        beginSession(origin: origin, phase: .ready, near: location)
        sourceText = text
    }

    /// Spinner while OCR reads the captured screenshot.
    func showRecognizing(near location: NSPoint) {
        beginSession(origin: .ocr, phase: .recognizing, near: location)
    }

    /// Whole-popup error (no text, missing permission).
    func show(error: String, settingsPane: SystemSettingsPane? = nil, near location: NSPoint) {
        beginSession(origin: origin, phase: .ready, near: location)
        popupError = PopupError(message: error, settingsPane: settingsPane)
    }

    /// Text-input mode: type or paste text to translate, no selection needed.
    func showComposing(near location: NSPoint, seed: String? = nil) {
        beginSession(origin: .typed, phase: .composing, near: location)
        if let seed { inputDraft = seed }
        focusRequest = UUID()
    }

    // MARK: - Translation flow

    /// Translates freshly-captured text to the user's default target,
    /// auto-flipping to the pair's other language when the text already IS
    /// the target, so a bare hotkey press always gives a useful result.
    func translateAndDisplay(text: String) async {
        sourceText = text
        phase = .ready

        let chosen = settings.targetLanguage
        var target = chosen
        autoFlipPending = false

        // Decide the flip locally from the script where possible, so "already
        // in the target language" costs zero extra requests.
        if settings.sourceLanguage == LanguageCatalog.autoCode {
            if let detected = ScriptDetector.detect(text) {
                if LanguageCatalog.matchesLanguage(detected, chosen) {
                    target = settings.partner(of: chosen)
                }
            } else if let bucket = ScriptDetector.detectScriptBucket(text) {
                // Safe locally only when exactly one enabled language uses
                // this script; otherwise the server's verdict decides.
                let candidates = settings.enabledLanguages.filter {
                    LanguageCatalog.script(for: $0) == bucket
                }
                if candidates.count == 1 {
                    if candidates[0] == chosen { target = settings.partner(of: chosen) }
                } else {
                    autoFlipPending = true
                }
            } else {
                autoFlipPending = true
            }
        }

        startTranslation(text: text, target: target)
    }

    /// User explicitly picked a target: honor it exactly, no auto-flip, and
    /// remember it as the default for the next capture.
    func retranslate(to target: String) {
        guard !sourceText.isEmpty else { return }
        settings.targetLanguage = target
        autoFlipPending = false
        startTranslation(text: sourceText, target: target)
    }

    /// Tone changed (popup control or Settings): re-run the current lookup.
    /// Cache keys include the tone, so tone-agnostic engines (Google) replay
    /// instantly from cache while Bing/Gemini fetch the new register.
    func toneChanged(_ tone: TranslationTone) {
        settings.tone = tone
        guard !sourceText.isEmpty, phase == .ready else { return }
        startTranslation(text: sourceText, target: targetCode)
    }

    /// User picked a source language ("auto" or a fixed code).
    func setSource(_ code: String) {
        settings.sourceLanguage = code
        autoFlipPending = false
        objectWillChange.send()
        if !sourceText.isEmpty { startTranslation(text: sourceText, target: targetCode) }
    }

    /// Swap source and target. With an auto source, the detected language
    /// becomes the new fixed source.
    func swapLanguages() {
        guard let source = effectiveSourceCode else { return }
        let oldTarget = targetCode
        settings.sourceLanguage = oldTarget
        settings.targetLanguage = source
        autoFlipPending = false
        if !sourceText.isEmpty {
            startTranslation(text: sourceText, target: source)
        } else {
            targetCode = source
        }
    }

    func submitDraft() {
        let text = inputDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        phase = .ready
        Task { await translateAndDisplay(text: text) }
    }

    func enterComposing() {
        inputDraft = sourceText
        phase = .composing
        refreshMonitors()
        focusRequest = UUID()
    }

    /// Re-run one engine only (card retry); keeps the session.
    func retry(engine: EngineID) {
        guard !sourceText.isEmpty else { return }
        let session = sessionID
        setCard(engine, status: .loading)
        let text = sourceText
        let target = targetCode
        let source = settings.sourceLanguage
        Task { @MainActor in
            do {
                let result = try await TranslationCoordinator.shared.translate(
                    text, to: target, from: source, using: engine)
                guard sessionID == session else { return }
                apply(TranslationCoordinator.Update(
                    engine: engine, outcome: .success(result),
                    isPrimary: primaryCard == nil))
            } catch let error as TranslationError {
                guard sessionID == session else { return }
                setCard(engine, status: .failure(error))
            } catch {
                guard sessionID == session else { return }
                setCard(engine, status: .failure(.network(error)))
            }
        }
    }

    func retryAll() {
        guard !sourceText.isEmpty else { return }
        startTranslation(text: sourceText, target: targetCode)
    }

    private func startTranslation(text: String, target: String) {
        streamTask?.cancel()
        sessionID = UUID()
        let session = sessionID

        sourceText = text
        targetCode = target
        phase = .ready
        popupError = nil
        resolvedSourceCode = nil
        spellingSuggestion = nil
        primaryEngine = nil

        // Display order is the user's configured order; the per-language
        // primary override only decides which result Copy/Speak act on, via
        // `primaryCard`, never the card positions.
        var engines = settings.orderedEnabledEngines
        engines.removeAll(where: sessionHiddenEngines.contains)
        cards = engines.map { EngineCardState(id: $0) }

        guard !engines.isEmpty else {
            popupError = PopupError(message: "All engines are disabled.", settingsPane: nil)
            return
        }

        let source = settings.sourceLanguage
        streamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let stream = await TranslationCoordinator.shared.translateAll(
                text, to: target, from: source, orderedEngines: engines)
            for await update in stream {
                guard self.sessionID == session else { return }
                self.apply(update)
            }
        }
    }

    private func apply(_ update: TranslationCoordinator.Update) {
        withAnimation(.easeOut(duration: 0.16)) {
            switch update.outcome {
            case .success(let result):
                setCard(update.engine, status: .success(result))
                // First writer wins on detection + spelling, so the header
                // and suggestion row never flicker between engines.
                if resolvedSourceCode == nil, let detected = result.detectedSourceLanguage {
                    resolvedSourceCode = LanguageCatalog.normalize(detected)
                }
                if spellingSuggestion == nil { spellingSuggestion = result.spellingSuggestion }
            case .failure(let error):
                setCard(update.engine, status: .failure(error))
            }
            if update.isPrimary { primaryEngine = update.engine }
        }

        // Deferred auto-flip: only the ambiguous-script case reaches here,
        // and only the first primary result carries the verdict.
        if autoFlipPending, update.isPrimary,
           case .success(let result) = update.outcome,
           let detected = result.detectedSourceLanguage,
           LanguageCatalog.matchesLanguage(detected, targetCode) {
            autoFlipPending = false
            startTranslation(text: sourceText, target: settings.partner(of: targetCode))
            return
        }
        if update.isPrimary { autoFlipPending = false }

        // After the flip check, so a flipped-away session never records: only
        // the session whose result the user actually sees reaches this line.
        if !primaryText.isEmpty {
            HistoryStore.shared.record(
                source: sourceText,
                translation: primaryText,
                sourceCode: effectiveSourceCode,
                targetCode: targetCode)
        }
    }

    /// Re-run a lookup from the history popover with its original target.
    /// A live translation (rather than showing the stored text) keeps the
    /// full card stack, speak, and copy behavior; the coordinator's cache
    /// usually answers instantly anyway.
    func recall(_ entry: HistoryEntry) {
        autoFlipPending = false
        startTranslation(text: entry.sourceText, target: entry.targetCode)
    }

    private func setCard(_ engine: EngineID, status: EngineStatus) {
        guard let index = cards.firstIndex(where: { $0.id == engine }) else { return }
        cards[index].status = status
    }

    // MARK: - Card actions

    func toggleExpanded(_ engine: EngineID) {
        guard let index = cards.firstIndex(where: { $0.id == engine }) else { return }
        cards[index].isExpanded.toggle()
    }

    /// Session-scoped hide; permanent disable lives in Settings.
    func hide(engine: EngineID) {
        withAnimation(.easeOut(duration: 0.16)) {
            sessionHiddenEngines.insert(engine)
            lastHiddenEngine = engine
        }
        undoChipTask?.cancel()
        undoChipTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { self?.lastHiddenEngine = nil }
        }
    }

    func undoHide() {
        guard let engine = lastHiddenEngine else { return }
        undoChipTask?.cancel()
        withAnimation(.easeOut(duration: 0.16)) {
            sessionHiddenEngines.remove(engine)
            lastHiddenEngine = nil
        }
    }

    func disablePermanently(engine: EngineID) {
        settings.enabledEngines.remove(engine)
        undoChipTask?.cancel()
        lastHiddenEngine = nil
        sessionHiddenEngines.remove(engine)
        cards.removeAll { $0.id == engine }
    }

    func copy(engine: EngineID) {
        guard let card = cards.first(where: { $0.id == engine }),
              case .success(let result) = card.status else { return }
        copyToPasteboard(result.translatedText)
    }

    func speak(engine: EngineID) {
        guard let card = cards.first(where: { $0.id == engine }),
              case .success(let result) = card.status else { return }
        SpeechService.shared.speak(result.translatedText, languageCode: targetCode)
    }

    // MARK: - Footer actions

    /// Speak the primary result in the target language.
    func speak() {
        guard !primaryText.isEmpty else { return }
        SpeechService.shared.speak(primaryText, languageCode: targetCode)
    }

    func speakSource() {
        guard !sourceText.isEmpty else { return }
        SpeechService.shared.speak(sourceText, languageCode: effectiveSourceCode)
    }

    func copyTranslation() {
        guard !primaryText.isEmpty else { return }
        copyToPasteboard(primaryText)
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Escape / close

    /// Staged escape: close an open picker, then leave composing (keeping the
    /// draft) when there are results to fall back to, then close.
    func handleEscape() {
        if isPickerOpen {
            isPickerOpen = false
            return
        }
        if phase == .composing, !inputDraft.isEmpty, !sourceText.isEmpty {
            phase = .ready
            refreshMonitors()
            return
        }
        close()
    }

    func close() {
        SpeechService.shared.stop()
        streamTask?.cancel()
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
        removeMonitors()
        panel?.orderOut(nil)
    }

    // MARK: - Auto-dismiss on mouse-away

    /// Polls the pointer against the panel frame (plus a grace margin — the
    /// popup spawns just outside the pointer, so the margin keeps a user who
    /// hasn't moved the mouse from losing the popup they're reading). Once
    /// the pointer stays beyond the zone for the configured delay, close.
    /// Pin, implicit pin (typing), and an open picker suspend the countdown.
    private func startAutoDismissMonitoring() {
        autoDismissTimer?.invalidate()
        awayAccumulated = 0
        guard settings.autoDismissEnabled else { autoDismissTimer = nil; return }
        let tick: TimeInterval = 0.25
        autoDismissTimer = Timer.scheduledTimer(withTimeInterval: tick, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.autoDismissTick(tick) }
        }
    }

    private func autoDismissTick(_ interval: TimeInterval) {
        guard let panel, panel.isVisible else {
            autoDismissTimer?.invalidate()
            autoDismissTimer = nil
            return
        }
        guard settings.autoDismissEnabled, !isPinned, !isImplicitlyPinned, !isPickerOpen else {
            awayAccumulated = 0
            return
        }
        let zone = panel.frame.insetBy(dx: -40, dy: -40)
        if zone.contains(NSEvent.mouseLocation) {
            awayAccumulated = 0
        } else {
            awayAccumulated += interval
            if awayAccumulated >= max(settings.autoDismissDelay, 0.5) {
                close()
            }
        }
    }

    // MARK: - Session reset

    /// Single reset for every entry point — the old four near-identical
    /// blocks drifted (show(error:) forgot half the fields).
    private func beginSession(
        origin: SourceOrigin, phase: SourcePhase, near location: NSPoint, takeFocus: Bool = true
    ) {
        streamTask?.cancel()
        sessionID = UUID()
        undoChipTask?.cancel()

        self.origin = origin
        self.phase = phase
        sourceText = ""
        resolvedSourceCode = nil
        spellingSuggestion = nil
        popupError = nil
        cards = []
        primaryEngine = nil
        lastHiddenEngine = nil
        sessionHiddenEngines = []
        autoFlipPending = false
        isPinned = false
        isPickerOpen = false
        targetCode = settings.targetLanguage
        // A fresh capture session clears a stale typed draft; opening
        // composing mode itself seeds the draft after this reset.
        if origin != .typed { inputDraft = "" }

        presentPanel(near: location, takeFocus: takeFocus)
    }

    // MARK: - Panel management

    private func presentPanel(near location: NSPoint, takeFocus: Bool = true) {
        let panel = ensurePanel()

        // Pinned means pinned in place: repeated lookups reuse the frame
        // instead of teleporting the window to the mouse.
        if !(isPinned && panel.isVisible) {
            let size = panel.frame.size
            var origin = NSPoint(x: location.x + 12, y: location.y - size.height - 12)
            if let screen = NSScreen.screens.first(where: { NSMouseInRect(location, $0.frame, false) })
                ?? NSScreen.main
            {
                let frame = screen.visibleFrame
                origin.x = min(max(origin.x, frame.minX + 8), frame.maxX - size.width - 8)
                origin.y = min(max(origin.y, frame.minY + 8), frame.maxY - size.height - 8)
            }
            panel.setFrameOrigin(origin)
        }
        panel.orderFrontRegardless()

        if takeFocus {
            panel.makeKey()
        }
        // Monitors are installed in every phase now — the capturing phase
        // used to have neither Esc nor click-outside, leaving a hung capture
        // undismissable for its whole timeout.
        refreshMonitors()
        startAutoDismissMonitoring()
    }

    private func ensurePanel() -> TranslationPanel {
        if let panel { return panel }

        let size = settings.popupSize
        let panel = TranslationPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless, .resizable],
            backing: .buffered,
            defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.minSize = SettingsStore.minPopupSize

        let hostingView = NSHostingView(rootView: PopupView(controller: self))
        hostingView.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hostingView

        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main
        ) { _ in
            Task { @MainActor in SettingsStore.shared.popupSize = panel.frame.size }
        }

        self.panel = panel
        return panel
    }

    // MARK: - Event monitors

    private var shouldCloseOnOutsideClick: Bool {
        // Composing with a non-empty draft is implicitly pinned so a stray
        // click can't destroy typing; the pin icon shows a dimmed state.
        !isPinned && !isPickerOpen && !(phase == .composing && !inputDraft.isEmpty)
    }

    var isImplicitlyPinned: Bool {
        !isPinned && phase == .composing && !inputDraft.isEmpty
    }

    func draftChanged() {
        refreshMonitors()
    }

    private func refreshMonitors() {
        guard panel?.isVisible == true else { return }

        if let clickOutsideMonitor {
            NSEvent.removeMonitor(clickOutsideMonitor)
            self.clickOutsideMonitor = nil
        }
        if shouldCloseOnOutsideClick {
            clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                Task { @MainActor in self?.close() }
            }
        }

        // Local Esc only works while the panel is key; the capturing phase
        // never takes key, so a global Esc monitor covers it.
        if escapeMonitor == nil {
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 {  // Esc
                    Task { @MainActor in self?.handleEscape() }
                    return nil
                }
                return event
            }
        }
        if globalEscapeMonitor == nil, phase == .capturing {
            globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 {
                    Task { @MainActor in self?.close() }
                }
            }
        } else if phase != .capturing, let globalEscapeMonitor {
            NSEvent.removeMonitor(globalEscapeMonitor)
            self.globalEscapeMonitor = nil
        }
    }

    private func removeMonitors() {
        if let clickOutsideMonitor {
            NSEvent.removeMonitor(clickOutsideMonitor)
            self.clickOutsideMonitor = nil
        }
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        if let globalEscapeMonitor {
            NSEvent.removeMonitor(globalEscapeMonitor)
            self.globalEscapeMonitor = nil
        }
    }
}
