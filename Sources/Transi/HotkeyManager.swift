import AppKit
import Carbon.HIToolbox

/// Global hotkey registration via Carbon's `RegisterEventHotKey` — no
/// dependencies, no Input Monitoring permission needed, and it works from a
/// pure `LSUIElement` app with no windows. One shared `InstallEventHandler`
/// dispatches every registered hotkey by its `EventHotKeyID`.
///
/// Each rebindable `TransiAction` maps to a Carbon hotkey via
/// `EventHotKeyID.id = UInt32(TransiAction.allCases.firstIndex(of: action))`.
/// That mapping is why `TransiAction`'s case order must never change — see
/// the warning on that enum.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    /// One live Carbon registration per action currently bound. Actions with
    /// `isRebindable == false` (`openSettings`) never appear here — they are
    /// `NSMenuItem` key equivalents instead, live only while the status-item
    /// menu is open.
    private var hotKeyRefs: [TransiAction: EventHotKeyRef] = [:]

    /// The app-supplied handler for each action, set once via `setHandlers`
    /// and invoked by the shared Carbon callback below.
    private var handlers: [TransiAction: () -> Void] = [:]

    private var eventHandler: EventHandlerRef?

    /// 'TRNS' — Transi's four-byte Carbon signature, distinguishing its
    /// hotkeys from any other app's in the shared `EventHotKeyID` namespace.
    private static let signature = OSType(0x5452_4E53)

    private init() {}

    /// Stores the action -> handler map. Called once by `AppDelegate` at
    /// launch, before `applyAll()`.
    func setHandlers(_ handlers: [TransiAction: () -> Void]) {
        self.handlers = handlers
    }

    /// (Re)registers every rebindable action from `ShortcutManager.shared`'s
    /// current bindings — a stored override where the user rebound one, the
    /// factory default otherwise. Safe to call repeatedly (e.g. after "Reset
    /// All to Defaults"): each registration first tears down whatever was
    /// registered for that action before.
    func applyAll() {
        for action in TransiAction.allCases where action.isRebindable {
            rebind(action, to: ShortcutManager.shared.binding(for: action))
        }
    }

    /// Registers `binding` as `action`'s live global hotkey, replacing
    /// whatever was registered for it before. Returns whether registration
    /// succeeded; on failure a human-readable reason is left in
    /// `HotkeyRegistration.shared.failureMessages[action]` (cleared again on
    /// the next successful registration for that action).
    @discardableResult
    func rebind(_ action: TransiAction, to binding: KeyBinding) -> Bool {
        guard action.isRebindable else { return false }

        // Carbon silently double-registers a combination that already has a
        // live hotkey under a different id rather than erroring, so any
        // previous registration for this action must be torn down first.
        unregister(action)

        ensureEventHandlerInstalled()

        // Stable id: this action's index into TransiAction.allCases, so the
        // callback below can map an incoming EventHotKeyID straight back to
        // an action without keeping a second lookup table in sync.
        let id = UInt32(TransiAction.allCases.firstIndex(of: action) ?? 0)
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let mask = CarbonModifiers.mask(for: binding.modifiers)

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(binding.keyCode), mask, hotKeyID, GetApplicationEventTarget(), 0, &ref)

        guard status == noErr, let ref else {
            HotkeyRegistration.shared.failureMessages[action] = failureMessage(for: binding)
            return false
        }

        hotKeyRefs[action] = ref
        HotkeyRegistration.shared.failureMessages[action] = nil
        return true
    }

    /// Tears down `action`'s live registration, if any. Leaves its handler in
    /// place — `rebind` calls this before registering the new combination,
    /// and the handler map is only ever replaced wholesale, by `setHandlers`.
    func unregister(_ action: TransiAction) {
        guard let ref = hotKeyRefs[action] else { return }
        UnregisterEventHotKey(ref)
        hotKeyRefs[action] = nil
    }

    /// Names whichever macOS shortcut already owns `binding`, if any.
    /// `RegisterEventHotKey` itself only ever reports `eventHotKeyExistsErr`
    /// — it never says who holds the combination — so `SystemHotkeys` reads
    /// the same `com.apple.symbolichotkeys` preferences System Settings does
    /// to name the culprit when it can.
    private func failureMessage(for binding: KeyBinding) -> String {
        var flags: NSEvent.ModifierFlags = []
        if binding.modifiers.contains(.command) { flags.insert(.command) }
        if binding.modifiers.contains(.shift) { flags.insert(.shift) }
        if binding.modifiers.contains(.option) { flags.insert(.option) }
        if binding.modifiers.contains(.control) { flags.insert(.control) }
        let match = SystemHotkeys.systemMatch(keyCode: binding.keyCode, modifiers: flags)
        return SystemHotkeys.message(for: match)
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
                let index = Int(hotKeyID.id)
                guard TransiAction.allCases.indices.contains(index) else { return noErr }
                let action = TransiAction.allCases[index]

                // Carbon invokes this handler on the main run loop, but the
                // callback itself is a plain C function pointer (no captures
                // allowed), so it can't be declared @MainActor. assumeIsolated
                // asserts what is already true in practice and lets it call
                // into the @MainActor manager synchronously.
                MainActor.assumeIsolated {
                    manager.handlers[action]?()
                }
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
