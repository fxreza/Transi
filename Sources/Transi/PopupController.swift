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
    @Published var sourceText: String = ""
    @Published var translatedText: String = ""
    @Published var detectedLanguage: String?
    @Published var spellingSuggestion: String?
    @Published var dictionary: [DictionaryEntry] = []
    @Published var isCapturing: Bool = false
    @Published var isLoading: Bool = false
    @Published var isAILoading: Bool = false
    @Published var isOCRLoading: Bool = false
    @Published var errorMessage: String?
    /// Set alongside `errorMessage` when the failure is a missing permission,
    /// so the popup can offer a button straight to the relevant settings pane.
    @Published var errorSettingsPane: SystemSettingsPane?
    @Published var effectiveTarget: TargetLanguage = .persian

    private var panel: TranslationPanel?
    private var clickOutsideMonitor: Any?
    private var escapeMonitor: Any?
    private var resizeObserver: Any?

    // MARK: - Public API

    /// Shows the popup the instant the hotkey fires, before the selection has
    /// been read. Reading the selection can take a moment in apps that need the
    /// copy-based fallbacks, and that used to be a completely silent gap — the
    /// hotkey appeared to do nothing until everything was finished.
    ///
    /// Deliberately does *not* take key focus: the capture strategies resolve the
    /// selection through the frontmost application, so stealing focus here would
    /// point them at our own panel and break the capture.
    func showCapturing(near location: NSPoint) {
        sourceText = ""
        translatedText = ""
        detectedLanguage = nil
        spellingSuggestion = nil
        dictionary = []
        errorMessage = nil
        errorSettingsPane = nil
        isCapturing = true
        isLoading = false
        isAILoading = false
        isOCRLoading = false
        effectiveTarget = Settings.shared.targetLanguage
        presentPanel(near: location, takeFocus: false)
    }

    func showTranslating(text: String, near location: NSPoint) {
        sourceText = text
        translatedText = ""
        detectedLanguage = nil
        spellingSuggestion = nil
        dictionary = []
        errorMessage = nil
        errorSettingsPane = nil
        isCapturing = false
        isLoading = true
        isAILoading = false
        isOCRLoading = false
        effectiveTarget = Settings.shared.targetLanguage
        presentPanel(near: location)
    }

    /// Shows the popup with a spinner while OCR reads the captured screenshot.
    func showRecognizing(near location: NSPoint) {
        sourceText = ""
        translatedText = ""
        detectedLanguage = nil
        spellingSuggestion = nil
        dictionary = []
        errorMessage = nil
        errorSettingsPane = nil
        isCapturing = false
        isLoading = false
        isAILoading = false
        isOCRLoading = true
        effectiveTarget = Settings.shared.targetLanguage
        presentPanel(near: location)
    }

    func show(
        error: String, settingsPane: SystemSettingsPane? = nil, near location: NSPoint
    ) {
        sourceText = ""
        translatedText = ""
        errorMessage = error
        errorSettingsPane = settingsPane
        isCapturing = false
        isLoading = false
        isOCRLoading = false
        presentPanel(near: location)
    }

    /// Translates a freshly-captured selection/screenshot to the user's default
    /// target, auto-flipping to the other language if the text already IS that
    /// target (fa <-> en) so a bare ⌥A/⌥S always gives a useful result.
    func translateAndDisplay(text: String) async {
        await translate(text: text, target: Settings.shared.targetLanguage, autoFlip: true)
    }

    /// User explicitly picked a language in the popup's segmented control: honor
    /// it exactly, with no auto-flip override, and remember it as the default
    /// target for the next capture.
    func retranslate(to target: TargetLanguage) {
        guard !sourceText.isEmpty else { return }
        Settings.shared.targetLanguage = target
        Task { await translate(text: sourceText, target: target, autoFlip: false) }
    }

    private func translate(text: String, target chosen: TargetLanguage, autoFlip: Bool) async {
        isCapturing = false
        isLoading = true
        errorMessage = nil
        errorSettingsPane = nil

        // Decide the auto-flip locally from the text's script where we can, so
        // "already in the target language" costs one request instead of two.
        var target = chosen
        var flipResolvedLocally = false
        if autoFlip, let script = ScriptDetector.detect(text) {
            flipResolvedLocally = true
            if script == chosen {
                target = chosen == .persian ? .english : .persian
            }
        }

        do {
            var result = try await TranslationService.shared.translate(text, to: target.rawValue)
            // Only ambiguous input (mixed or too short to call) still needs the
            // server's verdict, and only that case can cost a second request.
            if autoFlip, !flipResolvedLocally, let detected = result.detectedSourceLanguage,
               detected.lowercased().hasPrefix(target.rawValue) {
                target = target == .persian ? .english : .persian
                result = try await TranslationService.shared.translate(text, to: target.rawValue)
            }
            translatedText = result.translatedText
            detectedLanguage = result.detectedSourceLanguage
            spellingSuggestion = result.spellingSuggestion
            dictionary = result.dictionary
            effectiveTarget = target
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func aiTranslate() {
        guard !sourceText.isEmpty, ClaudeAIService.shared.isAvailable else { return }
        isAILoading = true
        let target = effectiveTarget
        let text = sourceText
        Task { @MainActor in
            do {
                let aiResult = try await ClaudeAIService.shared.translate(text, to: target)
                translatedText = aiResult
            } catch {
                errorMessage = error.localizedDescription
            }
            isAILoading = false
        }
    }

    /// Speak whichever side of the translation is English.
    func speak() {
        let english: String?
        if effectiveTarget == .english {
            english = translatedText.isEmpty ? nil : translatedText
        } else if detectedLanguage?.lowercased().hasPrefix("en") == true {
            english = sourceText
        } else {
            english = nil
        }
        guard let english else { return }
        SpeechService.shared.speakEnglish(english)
    }

    var canSpeak: Bool {
        if effectiveTarget == .english { return !translatedText.isEmpty }
        return detectedLanguage?.lowercased().hasPrefix("en") == true
    }

    func copyTranslation() {
        guard !translatedText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translatedText, forType: .string)
    }

    func close() {
        SpeechService.shared.stop()
        removeMonitors()
        panel?.orderOut(nil)
    }

    // MARK: - Panel management

    private func presentPanel(near location: NSPoint, takeFocus: Bool = true) {
        let panel = ensurePanel()
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
        panel.orderFrontRegardless()
        guard takeFocus else { return }
        panel.makeKey()
        installMonitors()
    }

    private func ensurePanel() -> TranslationPanel {
        if let panel { return panel }

        let size = Settings.shared.popupSize
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
        panel.minSize = Settings.minPopupSize

        let hostingView = NSHostingView(rootView: PopupView(controller: self))
        hostingView.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hostingView

        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main
        ) { _ in
            Task { @MainActor in Settings.shared.popupSize = panel.frame.size }
        }

        self.panel = panel
        return panel
    }

    private func installMonitors() {
        removeMonitors()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {  // Esc
                Task { @MainActor in self?.close() }
                return nil
            }
            return event
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
    }
}
