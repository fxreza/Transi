import Foundation

struct DictionaryMeaning: Sendable {
    let word: String
    let reverseTranslations: [String]
}

struct DictionaryEntry: Sendable {
    let partOfSpeech: String
    let meanings: [DictionaryMeaning]
}

/// The translation engines Transi can query. Raw values are persisted in
/// UserDefaults (engine order / enabled set), so they must stay stable.
enum EngineID: String, CaseIterable, Codable, Identifiable, Sendable {
    case google, bing, gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .google: return "Google"
        case .bing: return "Bing"
        case .gemini: return "Gemini"
        }
    }

    /// Only Gemini needs a user-supplied API key; Google and Bing use the
    /// same keyless web endpoints their translator sites use.
    var requiresKey: Bool { self == .gemini }
}

/// Translation register for the engines that support one. Bing's endpoint
/// takes it as a literal `tone` form field (the same control the website's
/// tone dropdown drives); Gemini takes it as a prompt instruction. Google's
/// endpoint has no tone support and always answers standard.
enum TranslationTone: String, CaseIterable, Codable, Identifiable {
    case standard, casual, formal

    var id: String { rawValue }
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// Value for Bing's `tone` body field; nil means omit the field.
    var bingValue: String? {
        switch self {
        case .standard: return nil
        case .casual: return "Casual"
        case .formal: return "Formal"
        }
    }

    /// Extra sentence for Gemini's system prompt; nil for standard.
    var geminiClause: String? {
        switch self {
        case .standard: return nil
        case .casual: return "Use a casual, colloquial, spoken register."
        case .formal: return "Use a formal, polite register."
        }
    }

    /// Read from UserDefaults directly so Sendable engines running off the
    /// main actor don't have to touch SettingsStore.
    static var current: TranslationTone {
        TranslationTone(rawValue: UserDefaults.standard.string(forKey: "translationTone") ?? "")
            ?? .standard
    }
}

/// What an engine can return beyond the bare translation. The popup uses this
/// to decide which affordances a result card gets.
enum EngineCapability: Sendable {
    case dictionary
    case transliteration
    case spellingSuggestion
}

/// One engine's complete answer for one lookup. Extends the fields the old
/// single-engine `TranslationResult` carried with the engine that produced it
/// and the transliteration Bing/Gemini can provide (Google's endpoint cannot).
struct EngineResult: Sendable {
    let engine: EngineID
    let translatedText: String
    let detectedSourceLanguage: String?
    let spellingSuggestion: String?
    let dictionary: [DictionaryEntry]
    let transliteration: String?
}

enum TranslationError: LocalizedError {
    case badResponse
    case http(Int)
    case network(Error)
    case textTooLong(limit: Int)
    /// Engine enabled but missing its API key (Gemini before setup).
    case notConfigured
    case invalidAPIKey
    case quotaExceeded
    /// Bing flagged the session for captcha; retried once already.
    case captcha
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .badResponse: return "Unexpected response from translation service."
        case .http(let code): return "Translation service returned HTTP \(code)."
        case .network(let err): return "Network error: \(err.localizedDescription)"
        case .textTooLong(let limit): return "Text is too long for this engine (limit \(limit) characters)."
        case .notConfigured: return "Add an API key in Settings to use this engine."
        case .invalidAPIKey: return "Invalid API key — check Settings."
        case .quotaExceeded: return "Free quota exceeded. Try again later."
        case .captcha: return "Temporarily unavailable (rate limited). Try again in a minute."
        case .rateLimited: return "Rate limited. Try again in a minute."
        }
    }
}

/// One translation backend. Implementations are stateless value types (any
/// mutable shared state, like Bing's scraped token, lives in its own actor)
/// so the coordinator can fire them concurrently without ceremony.
protocol TranslationEngine: Sendable {
    var id: EngineID { get }
    var capabilities: Set<EngineCapability> { get }

    /// Whether this engine can serve `language` (canonical catalog code).
    func supports(language: String) -> Bool

    /// Cheap readiness check the coordinator uses to skip an engine before
    /// spending a task-group slot on it (e.g. Gemini with no Keychain key).
    func isConfigured() -> Bool

    /// `source` is a canonical code or "auto"; each engine maps codes through
    /// `LanguageCatalog.engineCode(_:for:)` itself.
    func translate(_ text: String, to target: String, from source: String) async throws -> EngineResult
}

extension TranslationEngine {
    var displayName: String { id.displayName }
}

extension EngineCapability: Hashable {}
