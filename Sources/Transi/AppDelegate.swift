import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popup = PopupController()

    /// Items whose key-equivalent display tracks the rebindable shortcuts.
    private var actionMenuItems: [TransiAction: NSMenuItem] = [:]
    private var engineSubmenu: NSMenu!
    private var languageSubmenu: NSMenu!
    private var settingsKeyMonitor: Any?

    /// When the translate hotkey last fired, for the double-press shortcut in
    /// `translateCurrentSelection()`.
    private var lastTranslateHotkeyPress: Date?
    private static let doublePressWindow: TimeInterval = 0.8

    func applicationDidFinishLaunching(_ notification: Notification) {
        TextCapture.configureAccessibilityTimeout()
        promptForAccessibilityIfNeeded()
        ScreenCaptureManager.shared.requestPermissionIfNeeded()
        installEditMenu()
        setupStatusItem()
        TranslationCoordinator.shared.warmUpInBackground()
        registerHotkeys()
        installSettingsKeyMonitor()
        UpdateService.shared.checkOnLaunchIfNeeded()
    }

    // MARK: - Hotkeys

    private func registerHotkeys() {
        HotkeyManager.shared.setHandlers([
            .translateSelection: { [weak self] in
                Task { @MainActor in self?.translateCurrentSelection() }
            },
            .captureScreenshot: { [weak self] in
                Task { @MainActor in self?.captureScreenshotAndTranslate() }
            },
            .speakSelection: { [weak self] in
                Task { @MainActor in self?.speakCurrentSelection() }
            },
            .translateClipboard: { [weak self] in
                Task { @MainActor in self?.translateClipboard() }
            },
        ])
        HotkeyManager.shared.applyAll()
    }

    /// An LSUIElement app has no visible menu bar, but ⌘V/⌘C/⌘X/⌘A/⌘Z are
    /// dispatched through the main menu's Edit key equivalents — without one,
    /// keyboard paste is dead in every text field (API key field, search
    /// boxes, the type-to-translate input) and only the right-click menu
    /// works. This menu is never shown; it exists purely so the standard
    /// editing shortcuts resolve.
    private func installEditMenu() {
        let mainMenu = NSMenu()
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(
            withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    /// ⌘, opens Settings from any Transi window. A *local* monitor on
    /// purpose: it only sees events while a Transi window is key, so it can
    /// never steal ⌘, from other apps' own settings the way a global hotkey
    /// would. The menu's "Settings…" item is the always-available path.
    private func installSettingsKeyMonitor() {
        settingsKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               event.charactersIgnoringModifiers == "," {
                Task { @MainActor in SettingsWindowController.show() }
                return nil
            }
            return event
        }
    }

    // MARK: - Accessibility permission

    private func promptForAccessibilityIfNeeded() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            NSLog("Accessibility permission not yet granted; system prompt shown.")
        }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        // squareLength + a dedicated autosaveName, rather than variableLength and
        // the generic "Item-0" slot: the icon then asks for the least width it can
        // and remembers its own position, which is what keeps it from being the
        // first item macOS drops when the menu bar runs out of room. isVisible is
        // set explicitly so a stale hidden state can never carry over.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "TransiStatusItem"
        statusItem.isVisible = true
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "character.bubble",
                accessibilityDescription: "Transi")
        }

        let menu = NSMenu()

        // Key equivalents on these items are for display only — they mirror
        // the global hotkeys registered in HotkeyManager so the menu documents
        // them; `menuNeedsUpdate` keeps them in sync with rebinds.
        addActionItem(.translateSelection, action: #selector(menuTranslate), to: menu)
        addActionItem(.captureScreenshot, action: #selector(menuCaptureScreenshot), to: menu)
        addActionItem(.speakSelection, action: #selector(menuSpeakSelection), to: menu)

        menu.addItem(.separator())

        addActionItem(.translateClipboard, action: #selector(menuTranslateClipboard), to: menu)

        // No hotkey of its own: ⌥T with nothing selected opens the input
        // directly, this item is the explicit path.
        let typeItem = NSMenuItem(
            title: "Type Text to Translate…",
            action: #selector(menuTypeToTranslate), keyEquivalent: "")
        typeItem.target = self
        menu.addItem(typeItem)

        menu.addItem(.separator())

        let engineItem = NSMenuItem(title: "Engine", action: nil, keyEquivalent: "")
        engineSubmenu = NSMenu()
        engineItem.submenu = engineSubmenu
        menu.addItem(engineItem)

        let translateToItem = NSMenuItem(title: "Translate To", action: nil, keyEquivalent: "")
        languageSubmenu = NSMenu()
        translateToItem.submenu = languageSubmenu
        menu.addItem(translateToItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…", action: #selector(menuOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updatesItem = NSMenuItem(
            title: "Check for Updates…", action: #selector(menuCheckForUpdates), keyEquivalent: "")
        updatesItem.target = self
        menu.addItem(updatesItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "Quit Transi",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"))

        menu.delegate = self
        statusItem.menu = menu

        rebuildDynamicMenus()
    }

    @discardableResult
    private func addActionItem(
        _ action: TransiAction, action selector: Selector, to menu: NSMenu
    ) -> NSMenuItem {
        let item = NSMenuItem(title: action.label, action: selector, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        actionMenuItems[action] = item
        applyShortcutDisplay(to: item, for: action)
        return item
    }

    /// Mirrors the live binding onto the menu item. A binding whose key maps
    /// to a single character rides in `keyEquivalent`; anything else (arrows,
    /// F-keys) is appended to the title instead, since NSMenuItem's
    /// key-equivalent model is single-character only.
    private func applyShortcutDisplay(to item: NSMenuItem, for action: TransiAction) {
        let binding = ShortcutManager.shared.binding(for: action)
        let name = KeyBinding.keyName(keyCode: binding.keyCode)

        // Strip a previously appended glyph suffix.
        let baseTitle = action.label
        item.title = baseTitle

        if name.count == 1 {
            item.keyEquivalent = name.lowercased()
            var flags: NSEvent.ModifierFlags = []
            if binding.modifiers.contains(.command) { flags.insert(.command) }
            if binding.modifiers.contains(.shift) { flags.insert(.shift) }
            if binding.modifiers.contains(.option) { flags.insert(.option) }
            if binding.modifiers.contains(.control) { flags.insert(.control) }
            item.keyEquivalentModifierMask = flags
        } else {
            item.keyEquivalent = ""
            item.title = "\(baseTitle)  \(binding.display)"
        }
    }

    private func rebuildDynamicMenus() {
        let settings = SettingsStore.shared

        engineSubmenu.removeAllItems()
        let primary = settings.orderedEnabledEngines.first
        for engine in settings.orderedEnabledEngines {
            let item = NSMenuItem(
                title: engine.displayName,
                action: #selector(selectEngine(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = engine.rawValue
            item.state = engine == primary ? .on : .off
            engineSubmenu.addItem(item)
        }

        languageSubmenu.removeAllItems()
        for code in settings.enabledLanguages {
            let item = NSMenuItem(
                title: LanguageCatalog.language(for: code)?.displayName ?? code,
                action: #selector(selectTargetLanguage(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = code
            item.state = settings.targetLanguage == code ? .on : .off
            languageSubmenu.addItem(item)
        }
    }

    // MARK: - Menu actions

    @objc private func menuTranslate() { translateCurrentSelection() }
    @objc private func menuCaptureScreenshot() { captureScreenshotAndTranslate() }
    @objc private func menuSpeakSelection() { speakCurrentSelection() }
    @objc private func menuTranslateClipboard() { translateClipboard() }
    @objc private func menuTypeToTranslate() { typeToTranslate() }

    @objc private func menuOpenSettings() {
        SettingsWindowController.show()
    }

    @objc private func menuCheckForUpdates() {
        UpdateService.shared.checkForUpdates(silent: false)
    }

    @objc private func selectTargetLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String,
              LanguageCatalog.byCode[code] != nil else { return }
        SettingsStore.shared.targetLanguage = code
    }

    /// Clicking an engine makes it primary: moved to the front of the order,
    /// relative order of the rest preserved. One source of truth shared with
    /// the Engines tab's drag-reorder.
    @objc private func selectEngine(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let engine = EngineID(rawValue: raw) else { return }
        var order = SettingsStore.shared.engineOrder
        order.removeAll { $0 == engine }
        order.insert(engine, at: 0)
        SettingsStore.shared.engineOrder = order
    }

    // MARK: - Core flows

    /// Point-translate: one hotkey, four sources tried in order — selection,
    /// then the UI element under the pointer, then OCR around the pointer,
    /// then the type-text input. Each step is a strictly weaker guess than the
    /// last, so the user never has to decide which capture mode they want.
    private func translateCurrentSelection() {
        // Sampled once, at the moment the hotkey fires: it anchors the popup
        // *and* names the point we read text from, and those two must agree
        // even if the mouse moves while the capture runs.
        let mouseLocation = NSEvent.mouseLocation

        // Deliberate shortcut, not an accident of the fallback path: pressing
        // the hotkey again while the popup is still up jumps straight to the
        // input, so "⌥T ⌥T" is a two-tap way to type something to translate
        // without waiting out a capture that was never going to find text.
        let isDoublePress = popup.isPanelVisible
            && (lastTranslateHotkeyPress.map {
                Date().timeIntervalSince($0) < Self.doublePressWindow
            } ?? false)
        lastTranslateHotkeyPress = Date()
        if isDoublePress {
            popup.showComposing(near: mouseLocation)
            return
        }

        // Put the popup on screen before doing any work, so the hotkey always
        // has an immediate visible effect even when the capture needs a fallback.
        popup.showCapturing(near: mouseLocation)

        // Open the TLS connection while the selection is being read, so the
        // translation request doesn't pay for the handshake.
        TranslationCoordinator.shared.warmUpInBackground()

        Task { @MainActor in
            var captured = await TextCapture.selectedText()
            if captured == nil {
                // Nothing selected: read whatever the pointer is resting on —
                // a button, a label, an alert, or failing that OCR of the
                // pixels around it.
                captured = await PointerTextCapture.text(at: mouseLocation)
            }
            guard let text = captured else {
                // Nothing anywhere: fall into the input, so the one hotkey
                // covers "translate this" and "let me type something".
                popup.showComposing(near: mouseLocation)
                return
            }
            popup.showTranslating(text: text, near: mouseLocation)
            await popup.translateAndDisplay(text: text)
        }
    }

    private func translateClipboard() {
        let mouseLocation = NSEvent.mouseLocation
        TranslationCoordinator.shared.warmUpInBackground()
        guard let text = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            popup.show(error: "Clipboard has no text.", near: mouseLocation)
            return
        }
        popup.showTranslating(text: text, near: mouseLocation)
        Task { @MainActor in
            await popup.translateAndDisplay(text: text)
        }
    }

    private func typeToTranslate() {
        TranslationCoordinator.shared.warmUpInBackground()
        popup.showComposing(near: NSEvent.mouseLocation)
    }

    /// Reads the current selection aloud with an English voice. Language
    /// auto-detection mis-reads short English words ("Concise" as French, say),
    /// so this hotkey always pronounces English. Pressing the hotkey again on the
    /// same selection re-reads it slowly and a third press stops; SpeechService
    /// owns that cycle.
    private func speakCurrentSelection() {
        let mouseLocation = NSEvent.mouseLocation
        Task { @MainActor in
            guard let text = await TextCapture.selectedText() else {
                popup.show(error: "No text selected.", near: mouseLocation)
                return
            }
            SpeechService.shared.speakEnglish(text)
        }
    }

    private func captureScreenshotAndTranslate() {
        guard ScreenCaptureManager.shared.hasPermission else {
            ScreenCaptureManager.shared.requestPermissionIfNeeded()
            popup.show(
                error: "Screen Recording permission is needed for screenshot translate. "
                    + "Enable Transi in the list, then try again.",
                settingsPane: .screenRecording,
                near: NSEvent.mouseLocation)
            return
        }

        TranslationCoordinator.shared.warmUpInBackground()

        ScreenCaptureManager.shared.beginSelection { [weak self] image, point in
            guard let self else { return }
            guard let image else { return }
            Task { @MainActor in
                self.popup.showRecognizing(near: point)
                do {
                    let text = try await OCRService.recognizeText(in: image)
                    self.popup.showTranslating(text: text, near: point)
                    await self.popup.translateAndDisplay(text: text)
                } catch {
                    self.popup.show(error: error.localizedDescription, near: point)
                }
            }
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu == statusItem.menu else { return }
        // Enabled sets, order, and bindings can all change from Settings
        // while the menu is closed; rebuild the dynamic parts on open.
        rebuildDynamicMenus()
        for (action, item) in actionMenuItems {
            applyShortcutDisplay(to: item, for: action)
        }
    }
}
