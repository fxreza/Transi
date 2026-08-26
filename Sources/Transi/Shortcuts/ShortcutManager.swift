import Foundation
import Combine

// Adapted from Klip's Services/ShortcutManager.swift (MIT): same
// overrides-only persistence, resolved against `TransiAction.defaultBinding`
// instead of an in-window `ShortcutAction`. Transi's actions are global
// Carbon hotkeys (dispatched by `HotkeyManager`, not an `NSEvent` monitor),
// so this port drops Klip's `action(for: NSEvent)` lookup entirely — nothing
// here matches events, `HotkeyManager` decides which handler ran from the
// Carbon `EventHotKeyID` it received.

/// Owns the per-action key bindings: resolves each action's effective
/// `KeyBinding` (a stored override, or its default), persists only the
/// overrides, and detects conflicts before accepting a rebind.
@MainActor
final class ShortcutManager: ObservableObject {
    static let shared = ShortcutManager()

    enum ConflictResult: Equatable {
        case ok
        case conflict(TransiAction)
    }

    private static let storageKey = "shortcuts.bindings"
    private let defaults: UserDefaults

    /// Every action resolved to its effective binding: a stored override
    /// where one exists, `defaultBinding` otherwise. UserDefaults only ever
    /// stores the overrides (see `persist()`), so a future change to a
    /// default automatically applies to anyone who never rebound that action.
    @Published var bindings: [TransiAction: KeyBinding]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var resolved: [TransiAction: KeyBinding] = [:]
        for action in TransiAction.allCases {
            resolved[action] = action.defaultBinding
        }
        if let data = defaults.data(forKey: Self.storageKey),
           let overrides = try? JSONDecoder().decode([String: KeyBinding].self, from: data) {
            for (rawKey, binding) in overrides {
                // Unknown keys are skipped rather than treated as corruption,
                // so an override stored for an action that no longer exists
                // does not throw away the rest of the user's rebinds.
                if let action = TransiAction(rawValue: rawKey) {
                    resolved[action] = binding
                }
            }
        }
        self.bindings = resolved
    }

    func binding(for action: TransiAction) -> KeyBinding {
        bindings[action] ?? action.defaultBinding
    }

    func displayString(for action: TransiAction) -> String {
        binding(for: action).display
    }

    /// Attempts to bind `binding` to `action`. Refused (with the conflicting
    /// action returned) when another action already uses the identical key +
    /// modifier combination.
    @discardableResult
    func set(_ binding: KeyBinding, for action: TransiAction) -> ConflictResult {
        if let conflict = TransiAction.allCases.first(where: { $0 != action && self.binding(for: $0) == binding }) {
            return .conflict(conflict)
        }
        bindings[action] = binding
        persist()
        return .ok
    }

    func reset(action: TransiAction) {
        bindings[action] = action.defaultBinding
        persist()
    }

    func resetAll() {
        for action in TransiAction.allCases {
            bindings[action] = action.defaultBinding
        }
        persist()
    }

    private func persist() {
        var overrides: [String: KeyBinding] = [:]
        for action in TransiAction.allCases {
            let current = bindings[action] ?? action.defaultBinding
            if current != action.defaultBinding {
                overrides[action.rawValue] = current
            }
        }
        if overrides.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
        } else if let data = try? JSONEncoder().encode(overrides) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
