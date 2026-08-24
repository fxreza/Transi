import Foundation

struct DictionaryMeaning: Sendable {
    let word: String
    let reverseTranslations: [String]
}

struct DictionaryEntry: Sendable {
    let partOfSpeech: String
    let meanings: [DictionaryMeaning]
}

struct TranslationResult: Sendable {
    let translatedText: String
    let detectedSourceLanguage: String?
    let spellingSuggestion: String?
    let dictionary: [DictionaryEntry]
}

enum TranslationError: LocalizedError {
    case badResponse
    case http(Int)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .badResponse: return "Unexpected response from translation service."
        case .http(let code): return "Translation service returned HTTP \(code)."
        case .network(let err): return "Network error: \(err.localizedDescription)"
        }
    }
}

/// Free, keyless Google Translate client using the unofficial web endpoints.
/// Primary: translate.googleapis.com/translate_a/single (client=gtx)
/// Fallback: clients5.google.com/translate_a/t (client=dict-chrome-ex)
actor TranslationService {
    static let shared = TranslationService()

    private nonisolated let session: URLSession
    private var cache = [String: TranslationResult]()
    private var cacheOrder = [String]()
    private let cacheLimit = 200

    /// How long the primary endpoint gets on its own before the fallback is
    /// started alongside it. Short enough that a stalled primary no longer costs
    /// the full request timeout, long enough that the healthy path (~150-400ms)
    /// almost never fires a second request.
    private let hedgeDelay: Duration = .milliseconds(700)

    private var lastWarmUp: Date?
    private let warmUpInterval: TimeInterval = 60

    init() {
        let config = URLSessionConfiguration.ephemeral
        // Was 15s. A stalled request used to block the popup for the full
        // timeout before the fallback endpoint was even attempted; the hedge
        // below now covers slow responses, so this only bounds hard failures.
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 10
        // Fail fast instead of parking the request until the network returns.
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = [
            "User-Agent":
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
        ]
        session = URLSession(configuration: config)
    }

    func translate(_ text: String, to target: String, from source: String = "auto") async throws
        -> TranslationResult
    {
        let cacheKey = "\(source)|\(target)|\(text)"
        if let cached = cache[cacheKey] { return cached }

        let result = try await hedgedTranslate(text, to: target, from: source)
        storeInCache(result, for: cacheKey)
        return result
    }

    /// Runs the primary endpoint and, if it hasn't answered within `hedgeDelay`,
    /// the fallback endpoint alongside it. First success wins; the loser is
    /// cancelled. This replaces the old strictly-serial "primary, then on failure
    /// fallback" chain, where a slow primary meant paying its timeout in full
    /// before the fallback even started.
    private func hedgedTranslate(_ text: String, to target: String, from source: String)
        async throws -> TranslationResult
    {
        try await withThrowingTaskGroup(of: TranslationResult.self) { group in
            group.addTask { [self] in
                try await translatePrimary(text, to: target, from: source)
            }
            group.addTask { [self] in
                try await Task.sleep(for: hedgeDelay)
                return try await translateFallback(text, to: target, from: source)
            }

            var firstError: Error?
            while let outcome = await group.nextResult() {
                switch outcome {
                case .success(let result):
                    group.cancelAll()
                    return result
                case .failure(let error):
                    // Ignore the hedge losing its sleep race on cancellation.
                    if !(error is CancellationError), firstError == nil {
                        firstError = error
                    }
                }
            }
            throw firstError ?? TranslationError.badResponse
        }
    }

    /// Opens a TLS connection to the translate host so the next real request
    /// doesn't pay DNS + TCP + TLS setup. Called at launch and on each hotkey
    /// press, so the handshake overlaps the text-capture phase instead of
    /// landing in front of the user's translation.
    nonisolated func warmUpInBackground() {
        Task { await warmUp() }
    }

    private func warmUp() async {
        if let lastWarmUp, Date().timeIntervalSince(lastWarmUp) < warmUpInterval { return }
        lastWarmUp = Date()
        // A minimal real translate call: cheap, and primes the same connection
        // pool entry the next request will reuse.
        _ = try? await translatePrimary("a", to: "fa", from: "auto")
    }

    // MARK: - Primary endpoint (gtx)

    private nonisolated func translatePrimary(_ text: String, to target: String, from source: String)
        async throws -> TranslationResult
    {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: source),
            URLQueryItem(name: "tl", value: target),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "dt", value: "bd"),
            URLQueryItem(name: "dt", value: "qca"),
            URLQueryItem(name: "dj", value: "1"),
            URLQueryItem(name: "q", value: text),
        ]

        let data = try await fetch(components.url!)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranslationError.badResponse
        }

        var translated = ""
        if let sentences = json["sentences"] as? [[String: Any]] {
            for sentence in sentences {
                if let trans = sentence["trans"] as? String {
                    translated += trans
                }
            }
        }
        guard !translated.isEmpty else { throw TranslationError.badResponse }

        let detected = json["src"] as? String
        var spelling: String?
        if let spell = json["spell"] as? [String: Any],
           let spellRes = spell["spell_res"] as? String, !spellRes.isEmpty {
            spelling = spellRes
        }

        var dictionary = [DictionaryEntry]()
        if let dict = json["dict"] as? [[String: Any]] {
            for group in dict {
                let pos = group["pos"] as? String ?? ""
                var meanings = [DictionaryMeaning]()
                if let entries = group["entry"] as? [[String: Any]] {
                    for entry in entries {
                        guard let word = entry["word"] as? String else { continue }
                        let reverse = entry["reverse_translation"] as? [String] ?? []
                        meanings.append(
                            DictionaryMeaning(word: word, reverseTranslations: reverse))
                    }
                } else if let terms = group["terms"] as? [String] {
                    meanings = terms.map { DictionaryMeaning(word: $0, reverseTranslations: []) }
                }
                if !meanings.isEmpty {
                    dictionary.append(DictionaryEntry(partOfSpeech: pos, meanings: meanings))
                }
            }
        }

        return TranslationResult(
            translatedText: translated,
            detectedSourceLanguage: detected,
            spellingSuggestion: spelling,
            dictionary: dictionary)
    }

    // MARK: - Fallback endpoint (clients5)

    private nonisolated func translateFallback(_ text: String, to target: String, from source: String)
        async throws -> TranslationResult
    {
        var components = URLComponents(string: "https://clients5.google.com/translate_a/t")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "dict-chrome-ex"),
            URLQueryItem(name: "sl", value: source),
            URLQueryItem(name: "tl", value: target),
            URLQueryItem(name: "q", value: text),
        ]

        let data = try await fetch(components.url!)
        let json = try JSONSerialization.jsonObject(with: data)

        // Response shapes seen in the wild:
        //   ["translated"]  or  [["translated", "detectedLang"]]
        if let arr = json as? [Any] {
            if let first = arr.first as? String {
                return TranslationResult(
                    translatedText: first, detectedSourceLanguage: nil, spellingSuggestion: nil,
                    dictionary: [])
            }
            if let inner = arr.first as? [Any], let translated = inner.first as? String {
                let detected = inner.count > 1 ? inner[1] as? String : nil
                return TranslationResult(
                    translatedText: translated,
                    detectedSourceLanguage: detected,
                    spellingSuggestion: nil,
                    dictionary: [])
            }
        }
        throw TranslationError.badResponse
    }

    // MARK: - Helpers

    private nonisolated func fetch(_ url: URL) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw TranslationError.network(error)
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw TranslationError.http(http.statusCode)
        }
        return data
    }

    private func storeInCache(_ result: TranslationResult, for key: String) {
        if cache[key] == nil {
            cacheOrder.append(key)
            if cacheOrder.count > cacheLimit {
                let evicted = cacheOrder.removeFirst()
                cache[evicted] = nil
            }
        }
        cache[key] = result
    }
}
