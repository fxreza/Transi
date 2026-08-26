import Foundation
import AppKit

// Ported from Klip's Models/KeyBinding.swift (MIT). Klip itself adapted this
// from Clipfield. Transi uses these types for GLOBAL Carbon hotkeys
// (`HotkeyManager` + `CarbonModifiers`), not an in-window `NSEvent` monitor,
// so `matches(_:)` below is available for any future in-app shortcut UI but
// is not what drives the Carbon-registered hotkeys themselves.

/// The modifier keys a `KeyBinding` can require. `RawValue == Int` is
/// `Codable`, so this struct's compiler-synthesized `Codable` conformance
/// round-trips through a plain `{"rawValue": N}` JSON object.
struct KeyModifiers: OptionSet, Codable, Hashable {
    let rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    static let command = KeyModifiers(rawValue: 1 << 0)
    static let shift   = KeyModifiers(rawValue: 1 << 1)
    static let option  = KeyModifiers(rawValue: 1 << 2)
    static let control = KeyModifiers(rawValue: 1 << 3)

    /// Builds the set from an `NSEvent`'s modifier flags. Callers that care
    /// about exact-match semantics (see `KeyBinding.matches(_:)`) should
    /// intersect with `.deviceIndependentFlagsMask` first.
    init(eventFlags flags: NSEvent.ModifierFlags) {
        var result: KeyModifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        self = result
    }
}

/// A single key + modifier combination, e.g. one of Transi's global hotkeys.
///
/// Ordering in `display` follows the standard macOS `⌃⌥⇧⌘` convention (the
/// same one System Settings itself uses, e.g. `⇧⌘4`), so any shortcut shown
/// in Transi's UI reads the way the user expects.
struct KeyBinding: Codable, Equatable, Hashable {
    var keyCode: UInt16
    var modifiers: KeyModifiers

    init(keyCode: UInt16, modifiers: KeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Glyph string for display, e.g. `"⌥⌘C"`, `"⌘⌫"`, `"↩"`, `"⇥"`, `"Esc"`.
    var display: String {
        var out = ""
        if modifiers.contains(.control) { out += "⌃" }
        if modifiers.contains(.option) { out += "⌥" }
        if modifiers.contains(.shift) { out += "⇧" }
        if modifiers.contains(.command) { out += "⌘" }
        out += Self.keyName(keyCode: keyCode)
        return out
    }

    /// Whether `event` triggers this binding — exact match on key code *and*
    /// the device-independent modifier flags, so `⌘V` never matches `⌘⇧V`
    /// (or vice versa).
    func matches(_ event: NSEvent) -> Bool {
        guard event.keyCode == keyCode else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return KeyModifiers(eventFlags: flags) == modifiers
    }

    /// Display name for a raw key code: letters, digits, punctuation and
    /// space come from the `keyCodeNames` table below; everything else
    /// (arrows, return, tab, delete/forward-delete, escape, F1–F12) is named
    /// here.
    static func keyName(keyCode: UInt16) -> String {
        switch keyCode {
        case 36, 76: return "↩"   // Return / keypad enter
        case 48:     return "⇥"   // Tab
        case 51:     return "⌫"   // Delete (backspace)
        case 117:    return "⌦"   // Forward delete
        case 53:     return "Esc" // Escape
        case 123:    return "←"
        case 124:    return "→"
        case 125:    return "↓"
        case 126:    return "↑"
        case 122:    return "F1"
        case 120:    return "F2"
        case 99:     return "F3"
        case 118:    return "F4"
        case 96:     return "F5"
        case 97:     return "F6"
        case 98:     return "F7"
        case 100:    return "F8"
        case 101:    return "F9"
        case 109:    return "F10"
        case 103:    return "F11"
        case 111:    return "F12"
        default:
            return keyCodeNames[keyCode] ?? "Key\(keyCode)"
        }
    }
}

/// Map key codes to display names.
let keyCodeNames: [UInt16: String] = [
    0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
    8: "C", 9: "V", 10: "§", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
    16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
    24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
    32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K",
    41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
    49: "Space", 50: "`"
]
