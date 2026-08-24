import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popup = PopupController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        TextCapture.configureAccessibilityTimeout()
        promptForAccessibilityIfNeeded()
        ScreenCaptureManager.shared.requestPermissionIfNeeded()
        setupStatusItem()
        TranslationService.shared.warmUpInBackground()

        HotkeyManager.shared.registerTranslateHotkey { [weak self] in
            Task { @MainActor in self?.translateCurrentSelection() }
        }
        HotkeyManager.shared.registerScreenshotHotkey { [weak self] in
            Task { @MainActor in self?.captureScreenshotAndTranslate() }
        }
        HotkeyManager.shared.registerSpeakSelectionHotkey { [weak self] in
            Task { @MainActor in self?.speakCurrentSelection() }
        }
    }

    // MARK: - Accessibility permission

    private func promptForAccessibilityIfNeeded() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            NSLog("Accessibility permission not yet granted; system prompt shown.")
        }
    }

    /// The system's own permission alerts are shown at most once per app, so on
    /// any launch after the first the only way to get the user to the right pane
    /// is to open it ourselves. Menu items do that on demand.
    @objc private func menuOpenAccessibilitySettings() {
        SystemSettingsPane.accessibility.open()
    }

    @objc private func menuOpenScreenRecordingSettings() {
        SystemSettingsPane.screenRecording.open()
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

        // Key equivalents here are for display only — they mirror the global
        // hotkeys registered in HotkeyManager so the menu documents them. A status
        // item menu's key equivalents are only live while the menu is open.
        let translateItem = NSMenuItem(
            title: "Translate Selection",
            action: #selector(menuTranslate),
            keyEquivalent: "a")
        translateItem.keyEquivalentModifierMask = .option
        translateItem.target = self
        menu.addItem(translateItem)

        let screenshotItem = NSMenuItem(
            title: "Capture Screenshot to Translate",
            action: #selector(menuCaptureScreenshot),
            keyEquivalent: "d")
        screenshotItem.keyEquivalentModifierMask = .option
        screenshotItem.target = self
        menu.addItem(screenshotItem)

        let speakItem = NSMenuItem(
            title: "Read Selection Aloud",
            action: #selector(menuSpeakSelection),
            keyEquivalent: "s")
        speakItem.keyEquivalentModifierMask = .option
        speakItem.target = self
        menu.addItem(speakItem)

        menu.addItem(.separator())

        let targetHeader = NSMenuItem(title: "Translate To", action: nil, keyEquivalent: "")
        targetHeader.isEnabled = false
        menu.addItem(targetHeader)

        for lang in TargetLanguage.allCases {
            let item = NSMenuItem(
                title: lang.displayName,
                action: #selector(selectTargetLanguage(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = lang.rawValue
            item.state = Settings.shared.targetLanguage == lang ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let permissionsItem = NSMenuItem(title: "Permissions", action: nil, keyEquivalent: "")
        let permissionsMenu = NSMenu()
        for (title, action) in [
            ("Open Accessibility Settings", #selector(menuOpenAccessibilitySettings)),
            ("Open Screen Recording Settings", #selector(menuOpenScreenRecordingSettings)),
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            permissionsMenu.addItem(item)
        }
        permissionsItem.submenu = permissionsMenu
        menu.addItem(permissionsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Transi",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        menu.addItem(quitItem)

        menu.delegate = self
        statusItem.menu = menu
    }

    @objc private func menuTranslate() {
        translateCurrentSelection()
    }

    @objc private func menuCaptureScreenshot() {
        captureScreenshotAndTranslate()
    }

    @objc private func menuSpeakSelection() {
        speakCurrentSelection()
    }

    @objc private func selectTargetLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let lang = TargetLanguage(rawValue: raw) else { return }
        Settings.shared.targetLanguage = lang
    }

    // MARK: - Core flow

    private func translateCurrentSelection() {
        let mouseLocation = NSEvent.mouseLocation

        // Put the popup on screen before doing any work, so the hotkey always
        // has an immediate visible effect even when the capture needs a fallback.
        popup.showCapturing(near: mouseLocation)

        // Open the TLS connection while the selection is being read, so the
        // translation request doesn't pay for the handshake.
        TranslationService.shared.warmUpInBackground()

        Task { @MainActor in
            guard let text = await TextCapture.selectedText() else {
                popup.show(error: "No text selected.", near: mouseLocation)
                return
            }
            popup.showTranslating(text: text, near: mouseLocation)
            await popup.translateAndDisplay(text: text)
        }
    }

    /// Reads the current selection aloud with an English voice. Language
    /// auto-detection mis-reads short English words ("Concise" as French, say),
    /// so this hotkey always pronounces English. Pressing the hotkey again while
    /// speech is in progress stops it, so the same key both starts and cancels.
    private func speakCurrentSelection() {
        if SpeechService.shared.isSpeaking {
            SpeechService.shared.stop()
            return
        }

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
                    + "Enable Transi in the list, then try ⌥D again.",
                settingsPane: .screenRecording,
                near: NSEvent.mouseLocation)
            return
        }

        TranslationService.shared.warmUpInBackground()

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
        for item in menu.items {
            guard let raw = item.representedObject as? String,
                  let lang = TargetLanguage(rawValue: raw) else { continue }
            item.state = Settings.shared.targetLanguage == lang ? .on : .off
        }
    }
}
