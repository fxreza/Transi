import Carbon.HIToolbox

/// KeyModifiers -> Carbon modifier mask for RegisterEventHotKey.
///
/// Pulled out as a pure function (no Carbon calls, just the mask math) so
/// rebinding logic elsewhere can be tested against expected mask values
/// without going through `RegisterEventHotKey`/`UnregisterEventHotKey` and
/// their real, global side effects.
enum CarbonModifiers {
    static func mask(for modifiers: KeyModifiers) -> UInt32 {
        var mask: UInt32 = 0
        if modifiers.contains(.command) { mask |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { mask |= UInt32(shiftKey) }
        if modifiers.contains(.option) { mask |= UInt32(optionKey) }
        if modifiers.contains(.control) { mask |= UInt32(controlKey) }
        return mask
    }
}
