import Foundation
import Security

/// Minimal Keychain wrapper for the API keys Transi holds (today: Gemini).
/// Keys live in the login Keychain, never in UserDefaults — a defaults plist
/// is plain text on disk and ends up in backups and diagnostic dumps.
///
/// Keychain ACLs are tied to the code signature; `scripts/build-app.sh` signs
/// every build with the same local "Transi Dev" identity precisely so items
/// stored here stay readable across rebuilds without re-prompting.
enum KeychainStore {
    enum Key: String {
        case geminiAPIKey = "gemini_api_key"
    }

    private static let service = "com.fxreza.transi"

    static func read(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Delete-then-add upsert: simpler than branching add-vs-update, and
    /// writes are rare (the user pastes a key once). Items the app creates
    /// itself are readable without ACL prompts — including across rebuilds,
    /// since every build carries the same "Transi Dev" signature. An item
    /// created by another tool (e.g. the `security` CLI) prompts forever no
    /// matter what, so if the delete is refused and the add hits a duplicate,
    /// fall back to updating in place rather than silently failing.
    @discardableResult
    static func save(_ value: String, for key: Key) -> Bool {
        delete(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let match: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key.rawValue,
            ]
            let update: [String: Any] = [kSecValueData as String: Data(value.utf8)]
            return SecItemUpdate(match as CFDictionary, update as CFDictionary) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func delete(_ key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
