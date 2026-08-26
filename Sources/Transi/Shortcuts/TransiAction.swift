import Carbon.HIToolbox

/// Every action Transi can bind a keyboard shortcut to: the five global
/// hotkeys (registered with Carbon's `RegisterEventHotKey` by
/// `HotkeyManager`, live system-wide, no Input Monitoring permission needed)
/// plus `openSettings`, which is display-only — it is an `NSMenuItem` key
/// equivalent, live only while the status-item menu is open, never a Carbon
/// registration.
///
/// `CaseIterable`'s synthesized order (declaration order below) is load-bearing:
/// `HotkeyManager` uses each action's index into `TransiAction.allCases` as
/// its Carbon `EventHotKeyID.id`. Do not reorder these cases, and add any new
/// action at the end — reordering would remap old persisted hotkey IDs to the
/// wrong action on the next launch.
enum TransiAction: String, CaseIterable, Codable {
    case translateSelection  // ⌥T
    case captureScreenshot   // ⌥S
    case speakSelection      // ⌥R
    case translateClipboard  // ⌥C
    case openSettings        // ⌘, — display-only, never a Carbon hotkey

    var label: String {
        switch self {
        case .translateSelection: return "Translate Selection"
        case .captureScreenshot:  return "Capture Screenshot to Translate"
        case .speakSelection:     return "Read Selection Aloud"
        case .translateClipboard: return "Translate Clipboard"
        case .openSettings:       return "Open Settings"
        }
    }

    /// `false` only for `openSettings`: it is an `NSMenuItem` key equivalent
    /// (live only while the status-item menu is open), not a global Carbon
    /// hotkey, so there is nothing for `HotkeyManager` to register or rebind.
    /// The Shortcuts tab shows its row greyed out with no recorder.
    var isRebindable: Bool {
        self != .openSettings
    }

    /// The factory key + modifier combination, restored by "Reset" / "Reset
    /// All to Defaults".
    ///
    /// Mnemonic ⌥-plus-letter family: ⌥T Translate, ⌥S Screenshot, ⌥R Read,
    /// ⌥C Clipboard — each letter is the action, replacing the arbitrary
    /// ⌥A/⌥D/⌥S set inherited from Easydict's defaults. There is no
    /// type-to-translate hotkey: ⌥T with nothing selected opens the input
    /// directly, and the status-bar menu keeps an explicit item. Deliberately
    /// nothing on ⌥Q / ⌥W: those sit directly under ⌘Q and ⌘W, so a slipped
    /// modifier quits the app or closes the frontmost window instead of doing
    /// the intended action. `openSettings` uses ⌘, — the standard macOS
    /// "Preferences" key equivalent — rather than the ⌥ family, since it is
    /// never a global hotkey and macOS users already expect ⌘, for settings.
    var defaultBinding: KeyBinding {
        switch self {
        case .translateSelection: return KeyBinding(keyCode: UInt16(kVK_ANSI_T), modifiers: [.option])
        case .captureScreenshot:  return KeyBinding(keyCode: UInt16(kVK_ANSI_S), modifiers: [.option])
        case .speakSelection:     return KeyBinding(keyCode: UInt16(kVK_ANSI_R), modifiers: [.option])
        case .translateClipboard: return KeyBinding(keyCode: UInt16(kVK_ANSI_C), modifiers: [.option])
        case .openSettings:       return KeyBinding(keyCode: UInt16(kVK_ANSI_Comma), modifiers: [.command])
        }
    }
}
