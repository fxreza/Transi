import Foundation

/// API-key storage in a user-only file, NOT the Keychain — a deliberate
/// trade-off forced by the signing setup.
///
/// The Keychain gates silent access on the app's Team ID (its "partition").
/// Transi is signed with a self-signed local identity that has no Team ID, so
/// every rebuild looks like a different app to the keychain's partition check
/// and macOS demands the login-keychain *password* on each access — "Always
/// Allow" can never stick. The only real keychain fix is an Apple-issued
/// Developer ID; until one exists, a file at
/// `~/Library/Application Support/Transi/` with 0600 permissions (readable by
/// this user account only) is the honest alternative: same on-disk exposure
/// class as ~/.netrc or an .env file, and zero prompts.
///
/// The type keeps its old name so call sites read unchanged; values are
/// cached in memory after the first read (engines read on every translate).
enum KeychainStore {
    enum Key: String {
        case geminiAPIKey = "gemini_api_key"
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [Key: String?] = [:]

    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Transi", isDirectory: true)
    }

    private static func fileURL(for key: Key) -> URL {
        directory.appendingPathComponent(key.rawValue)
    }

    static func read(_ key: Key) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cache[key] { return cached }
        let value = (try? String(contentsOf: fileURL(for: key), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let result = (value?.isEmpty == false) ? value : nil
        cache[key] = result
        return result
    }

    @discardableResult
    static func save(_ value: String, for key: Key) -> Bool {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let url = fileURL(for: key)
            try Data(value.utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: url.path)
            cache[key] = value
            return true
        } catch {
            NSLog("KeychainStore: failed to save \(key.rawValue): \(error)")
            return false
        }
    }

    static func delete(_ key: Key) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        try? FileManager.default.removeItem(at: fileURL(for: key))
        cache[key] = String?.none
    }
}
