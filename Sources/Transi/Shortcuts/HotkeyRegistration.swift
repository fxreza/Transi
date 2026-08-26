import Foundation
import Combine

/// Live status of each action's Carbon hotkey registration, published so
/// `ShortcutsView` can show a red caption under a row without `HotkeyManager`
/// depending on SwiftUI.
///
/// `HotkeyManager` sets an entry when `RegisterEventHotKey` refuses a
/// combination (already owned by macOS or another app) and clears it the
/// moment that action registers successfully — so a caption never lingers
/// after the user records a working combination.
@MainActor
final class HotkeyRegistration: ObservableObject {
    static let shared = HotkeyRegistration()

    @Published var failureMessages: [TransiAction: String] = [:]

    private init() {}
}
