import AppKit
import Carbon.HIToolbox

/// Global hotkey registration via Carbon RegisterEventHotKey (no dependencies,
/// no Input Monitoring permission needed). Supports multiple hotkeys, dispatched
/// by their EventHotKeyID.
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var callbacks: [UInt32: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1

    /// Register ⌥A as the global translate hotkey.
    ///
    /// Deliberately not ⌥Q / ⌥W: those sit directly under ⌘Q and ⌘W, so a
    /// slipped modifier quits the app or closes the frontmost window instead of
    /// translating.
    func registerTranslateHotkey(_ handler: @escaping () -> Void) {
        register(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey), handler: handler)
    }

    /// Register ⌥S as the global screenshot-OCR-translate hotkey.
    func registerScreenshotHotkey(_ handler: @escaping () -> Void) {
        register(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(optionKey), handler: handler)
    }

    @discardableResult
    private func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> Bool {
        ensureEventHandlerInstalled()

        let id = nextID
        nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x5154_524E), id: id)  // 'QTRN'

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }

        hotKeyRefs[id] = ref
        callbacks[id] = handler
        return true
    }

    private func ensureEventHandlerInstalled() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData, let event else { return noErr }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID)
                guard status == noErr else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.callbacks[hotKeyID.id]?()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler)
    }

    deinit {
        for (_, ref) in hotKeyRefs { UnregisterEventHotKey(ref) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
