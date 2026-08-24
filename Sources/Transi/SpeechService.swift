import AVFoundation
import Foundation
import NaturalLanguage

/// Text-to-speech using the built-in macOS synthesizer (offline, free).
final class SpeechService: NSObject {
    static let shared = SpeechService()

    private let synthesizer = AVSpeechSynthesizer()

    /// Speak English text aloud. Stops any speech already in progress.
    func speakEnglish(_ text: String) {
        speak(text, languageCode: "en-US")
    }

    /// Speak arbitrary text aloud, guessing the language when none is given so
    /// the synthesizer doesn't read, say, Persian with an English voice. Falls
    /// back to the system default voice when no voice is installed for the
    /// detected language.
    func speak(_ text: String, languageCode: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        stop()
        let utterance = AVSpeechUtterance(string: trimmed)
        let code = languageCode ?? Self.detectLanguageCode(trimmed)
        if let code, let voice = AVSpeechSynthesisVoice(language: code) {
            utterance.voice = voice
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    /// BCP-47 code for the dominant language, or `nil` when the sample is too
    /// short or too mixed to call.
    private static func detectLanguageCode(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }
}
