import AppKit
import SwiftUI

/// The Settings window's tabs, in `TabView` order.
enum SettingsTab: Int {
    case general, languages, engines, shortcuts, appearance, permissions
}

/// Drives which tab `SettingsView`'s `TabView` shows. A singleton rather
/// than state owned by the window controller because `show(tab:)` needs to
/// switch tabs on an already-open window from outside SwiftUI.
@MainActor
final class SettingsTabSelection: ObservableObject {
    static let shared = SettingsTabSelection()
    @Published var tab: SettingsTab = .general
    private init() {}
}

/// Owns the single Settings window: a plain `NSWindow` wrapping a SwiftUI
/// root via `NSHostingController`, matching how the rest of Transi hosts
/// windows — the app is `LSUIElement`/`.accessory`, so there is no
/// menu-bar-driven `Scene` lifecycle to hook a SwiftUI `Settings` scene into.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static var current: SettingsWindowController?

    /// Shows the Settings window, creating it on first use. A second call
    /// re-fronts the existing window; passing `tab` also switches it.
    static func show(tab: SettingsTab? = nil) {
        if let tab {
            SettingsTabSelection.shared.tab = tab
        }
        let controller = current ?? SettingsWindowController()
        current = controller
        controller.showWindow(nil)
    }

    private init() {
        let hostingController = NSHostingController(
            rootView: SettingsView(selectedTab: SettingsTabSelection.shared))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Transi Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// `makeKeyAndOrderFront` alone can leave an `.accessory` app's window
    /// behind whatever app is currently frontmost; `NSApp.activate` is what
    /// actually brings keyboard focus here, which the Shortcuts tab's
    /// recorder fields depend on just as much as the user does.
    override func showWindow(_ sender: Any?) {
        PermissionsState.shared.startPolling()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        PermissionsState.shared.stopPolling()
        Self.current = nil
    }
}
