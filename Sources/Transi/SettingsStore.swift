import AppKit
import Combine

/// App settings persisted in UserDefaults. Grown from the old `Settings`
/// class into an `ObservableObject` so the Settings tabs and the popup can
/// bind to it directly; non-SwiftUI callers keep the same synchronous
/// property access they had before.
///
/// Every `@Published` property writes UserDefaults from its `didSet`, gated
/// on `isLoaded` so loading stored values during `init` doesn't write them
/// straight back.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard
    private var isLoaded = false

    // MARK: - Languages

    /// Canonical catalog code of the default translate-to language.
    /// Key and raw values ("fa"/"en") are unchanged from the shipped
    /// two-language version, so upgrades need no migration.
    @Published var targetLanguage: String = "fa" {
        didSet { if isLoaded { defaults.set(targetLanguage, forKey: "targetLanguage") } }
    }

    /// The other half of the user's working pair: when detected source equals
    /// the target, translation flips here so a bare hotkey press is always
    /// useful. Defaults to the fa/en partner of `targetLanguage`.
    @Published var secondaryLanguage: String = "en" {
        didSet { if isLoaded { defaults.set(secondaryLanguage, forKey: "secondaryLanguage") } }
    }

    /// Languages offered in the popup pickers and the menu. Always kept a
    /// superset of {target, secondary} — see `enabledLanguages`.
    @Published var enabledLanguageCodes: [String] = [] {
        didSet { if isLoaded { defaults.set(enabledLanguageCodes, forKey: "enabledLanguages") } }
    }

    /// "auto" or a fixed canonical code.
    @Published var sourceLanguage: String = LanguageCatalog.autoCode {
        didSet { if isLoaded { defaults.set(sourceLanguage, forKey: "sourceLanguage") } }
    }

    /// The enabled set with the target/secondary guarantee applied, in stored
    /// order. UI iterates this, never `enabledLanguageCodes` directly.
    var enabledLanguages: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for code in enabledLanguageCodes + [targetLanguage, secondaryLanguage]
        where LanguageCatalog.byCode[code] != nil && seen.insert(code).inserted {
            out.append(code)
        }
        return out
    }

    // MARK: - Engines

    /// All engines in display/failover order. Order is meaningful even for
    /// disabled engines so toggling one off and on doesn't lose its place.
    @Published var engineOrder: [EngineID] = [.google, .bing, .gemini] {
        didSet { if isLoaded { defaults.set(engineOrder.map(\.rawValue), forKey: "engineOrder") } }
    }

    /// Gemini stays off until the user adds a key.
    @Published var enabledEngines: Set<EngineID> = [.google, .bing] {
        didSet { if isLoaded { defaults.set(enabledEngines.map(\.rawValue).sorted(), forKey: "enabledEngines") } }
    }

    /// Per-target-language primary-engine override (canonical code → engine).
    @Published var perLanguageEngineOverride: [String: EngineID] = [:] {
        didSet {
            if isLoaded {
                defaults.set(perLanguageEngineOverride.mapValues(\.rawValue), forKey: "perLanguageEngineOverride")
            }
        }
    }

    /// Register for engines that support one (Bing, Gemini). The popup's
    /// tone control and the Engines tab both bind here.
    @Published var tone: TranslationTone = .standard {
        didSet { if isLoaded { defaults.set(tone.rawValue, forKey: "translationTone") } }
    }

    @Published var geminiModel: String = "gemini-3.7-flash" {
        didSet { if isLoaded { defaults.set(geminiModel, forKey: "geminiModel") } }
    }

    @Published var hasAcknowledgedGeminiPrivacyNote: Bool = false {
        didSet { if isLoaded { defaults.set(hasAcknowledgedGeminiPrivacyNote, forKey: "geminiPrivacyNoteAcknowledged") } }
    }

    /// Enabled engines in failover order. First entry is the default primary.
    var orderedEnabledEngines: [EngineID] {
        engineOrder.filter { enabledEngines.contains($0) }
    }

    /// The engine whose result is "primary" (reserved top card, copy target)
    /// for a given target language: per-language override first, then the
    /// first enabled engine in order.
    func primaryEngine(forTarget code: String) -> EngineID? {
        if let override = perLanguageEngineOverride[code], enabledEngines.contains(override) {
            return override
        }
        return orderedEnabledEngines.first
    }

    /// For UI gating only — the key itself lives in the Keychain.
    var hasGeminiKey: Bool { KeychainStore.read(.geminiAPIKey) != nil }

    // MARK: - Updates

    @Published var includePrereleases: Bool = false {
        didSet { if isLoaded { defaults.set(includePrereleases, forKey: "includePrereleases") } }
    }

    // MARK: - Appearance

    @Published var accentTheme: AccentTheme = .system {
        didSet { if isLoaded { defaults.set(accentTheme.rawValue, forKey: "accentTheme") } }
    }

    @Published var colorScheme: AppColorScheme = .system {
        didSet { if isLoaded { defaults.set(colorScheme.rawValue, forKey: "colorScheme") } }
    }

    /// Multiplier on the popup's base text sizes (0.8...1.6).
    @Published var popupTextSize: Double = 1.0 {
        didSet { if isLoaded { defaults.set(popupTextSize, forKey: "popupTextSize") } }
    }

    /// Renders the popup's controls (language pickers, swap/pin/close, card
    /// action icons) ~35% larger. Separate from `popupTextSize`, which only
    /// scales the text being read.
    @Published var largePopupControls: Bool = false {
        didSet { if isLoaded { defaults.set(largePopupControls, forKey: "largePopupControls") } }
    }

    // MARK: - Popup window

    /// Close the popup on its own once the pointer has stayed away from the
    /// window for `autoDismissDelay` seconds. Pin, an open picker, and
    /// composing with a draft all suspend it.
    @Published var autoDismissEnabled: Bool = true {
        didSet { if isLoaded { defaults.set(autoDismissEnabled, forKey: "autoDismissEnabled") } }
    }

    @Published var autoDismissDelay: Double = 2.0 {
        didSet { if isLoaded { defaults.set(autoDismissDelay, forKey: "autoDismissDelay") } }
    }

    static let minPopupSize = NSSize(width: 380, height: 280)
    static let defaultPopupSize = NSSize(width: 480, height: 420)

    /// Popup window size, remembered across launches once the user resizes it.
    var popupSize: NSSize {
        get {
            let width = defaults.object(forKey: "popupWidth") as? CGFloat
                ?? Self.defaultPopupSize.width
            let height = defaults.object(forKey: "popupHeight") as? CGFloat
                ?? Self.defaultPopupSize.height
            return NSSize(
                width: max(width, Self.minPopupSize.width),
                height: max(height, Self.minPopupSize.height))
        }
        set {
            defaults.set(newValue.width, forKey: "popupWidth")
            defaults.set(newValue.height, forKey: "popupHeight")
        }
    }

    func resetPopupSize() {
        defaults.removeObject(forKey: "popupWidth")
        defaults.removeObject(forKey: "popupHeight")
    }

    // MARK: - Init / load

    private init() {
        if let raw = defaults.string(forKey: "targetLanguage"), LanguageCatalog.byCode[raw] != nil {
            targetLanguage = raw
        }
        if let raw = defaults.string(forKey: "secondaryLanguage"), LanguageCatalog.byCode[raw] != nil {
            secondaryLanguage = raw
        } else {
            secondaryLanguage = targetLanguage == "fa" ? "en" : "fa"
        }
        if let stored = defaults.array(forKey: "enabledLanguages") as? [String] {
            enabledLanguageCodes = stored.filter { LanguageCatalog.byCode[$0] != nil }
        }
        if enabledLanguageCodes.isEmpty {
            enabledLanguageCodes = [targetLanguage, secondaryLanguage]
        }
        if let raw = defaults.string(forKey: "sourceLanguage"),
           raw == LanguageCatalog.autoCode || LanguageCatalog.byCode[raw] != nil {
            sourceLanguage = raw
        }

        if let stored = defaults.array(forKey: "engineOrder") as? [String] {
            let decoded = stored.compactMap(EngineID.init(rawValue:))
            // Engines added in later versions append at the end rather than
            // vanishing from the order.
            if !decoded.isEmpty {
                engineOrder = decoded + EngineID.allCases.filter { !decoded.contains($0) }
            }
        }
        if let stored = defaults.array(forKey: "enabledEngines") as? [String] {
            enabledEngines = Set(stored.compactMap(EngineID.init(rawValue:)))
            if enabledEngines.isEmpty { enabledEngines = [.google] }
        }
        if let stored = defaults.dictionary(forKey: "perLanguageEngineOverride") as? [String: String] {
            perLanguageEngineOverride = stored.compactMapValues(EngineID.init(rawValue:))
        }
        if let raw = defaults.string(forKey: "translationTone"), let stored = TranslationTone(rawValue: raw) {
            tone = stored
        }
        if let raw = defaults.string(forKey: "geminiModel"), !raw.isEmpty {
            geminiModel = raw
        }
        hasAcknowledgedGeminiPrivacyNote = defaults.bool(forKey: "geminiPrivacyNoteAcknowledged")
        includePrereleases = defaults.bool(forKey: "includePrereleases")

        if let raw = defaults.string(forKey: "accentTheme"), let theme = AccentTheme(rawValue: raw) {
            accentTheme = theme
        }
        if let raw = defaults.string(forKey: "colorScheme"), let scheme = AppColorScheme(rawValue: raw) {
            colorScheme = scheme
        }
        let storedTextSize = defaults.double(forKey: "popupTextSize")
        if storedTextSize > 0 { popupTextSize = min(max(storedTextSize, 0.8), 1.6) }

        largePopupControls = defaults.bool(forKey: "largePopupControls")
        if defaults.object(forKey: "autoDismissEnabled") != nil {
            autoDismissEnabled = defaults.bool(forKey: "autoDismissEnabled")
        }
        let storedDelay = defaults.double(forKey: "autoDismissDelay")
        if storedDelay > 0 { autoDismissDelay = min(max(storedDelay, 0.5), 10) }

        isLoaded = true
    }

    // MARK: - Language pair helpers

    /// The "other" language of the user's default pair, used by auto-flip:
    /// translating into `target` when the text already IS `target` flips here.
    /// A manually picked third language flips back to the secondary.
    func partner(of target: String) -> String {
        target == secondaryLanguage ? targetLanguage : secondaryLanguage
    }
}
