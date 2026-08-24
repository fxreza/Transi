import Foundation

/// Cheap, local language guess based on which script the text is written in.
///
/// Used to decide the auto-flip target (fa <-> en) *before* any network call.
/// Previously the flip was decided from Google's `src` field in the response,
/// which meant every "text is already in the target language" case cost a second
/// full round trip to translate the exact same string.
enum ScriptDetector {

    /// Returns the language the text appears to be written in, or `nil` when the
    /// sample is too mixed or too small to call confidently. `nil` means "ask the
    /// server", so ambiguous input still gets the old behaviour.
    static func detect(_ text: String) -> TargetLanguage? {
        var arabicScript = 0
        var latin = 0

        for scalar in text.unicodeScalars {
            switch scalar.value {
            // Arabic, Arabic Supplement, Arabic Extended-A, and the two
            // presentation-forms blocks. Persian shares all of these.
            case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF,
                 0xFB50...0xFDFF, 0xFE70...0xFEFF:
                arabicScript += 1
            case 0x0041...0x005A, 0x0061...0x007A:
                latin += 1
            default:
                continue
            }
        }

        let total = arabicScript + latin
        // Too few letters to judge (numbers, punctuation, emoji, symbols).
        guard total >= 2 else { return nil }

        // Require a clear majority; mixed-script text falls through to the server.
        let threshold = Double(total) * 0.7
        if Double(arabicScript) >= threshold { return .persian }
        if Double(latin) >= threshold { return .english }
        return nil
    }
}
