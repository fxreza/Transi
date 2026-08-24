import AppKit

enum TargetLanguage: String, CaseIterable {
    case persian = "fa"
    case english = "en"

    var displayName: String {
        switch self {
        case .persian: return "Persian (فارسی)"
        case .english: return "English"
        }
    }
}

/// App settings persisted in UserDefaults.
final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard
    private let targetLanguageKey = "targetLanguage"
    private let popupWidthKey = "popupWidth"
    private let popupHeightKey = "popupHeight"

    static let minPopupSize = NSSize(width: 320, height: 220)
    private static let defaultPopupSize = NSSize(width: 420, height: 320)

    var targetLanguage: TargetLanguage {
        get {
            guard let raw = defaults.string(forKey: targetLanguageKey),
                  let lang = TargetLanguage(rawValue: raw) else { return .persian }
            return lang
        }
        set { defaults.set(newValue.rawValue, forKey: targetLanguageKey) }
    }

    /// Popup window size, remembered across launches once the user resizes it.
    var popupSize: NSSize {
        get {
            let width = defaults.object(forKey: popupWidthKey) as? CGFloat
                ?? Self.defaultPopupSize.width
            let height = defaults.object(forKey: popupHeightKey) as? CGFloat
                ?? Self.defaultPopupSize.height
            return NSSize(
                width: max(width, Self.minPopupSize.width),
                height: max(height, Self.minPopupSize.height))
        }
        set {
            defaults.set(newValue.width, forKey: popupWidthKey)
            defaults.set(newValue.height, forKey: popupHeightKey)
        }
    }

    /// Effective target for a piece of text: if the detected source already equals
    /// the chosen target (e.g. Persian text while targeting Persian), flip to the
    /// other language so translation is always useful.
    func effectiveTarget(forDetected detected: String?) -> TargetLanguage {
        let chosen = targetLanguage
        guard let detected else { return chosen }
        if detected.lowercased().hasPrefix(chosen.rawValue) {
            return chosen == .persian ? .english : .persian
        }
        return chosen
    }
}
