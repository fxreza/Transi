import Foundation
import SwiftUI

/// Root shell for the Settings window: six tabs plus a version footer.
/// Every tab binds directly to `SettingsStore.shared` — there is no
/// separate view-model layer, and every change applies immediately (this
/// matches how native macOS Settings panes behave).
struct SettingsView: View {
    @ObservedObject var selectedTab: SettingsTabSelection

    @MainActor
    init(selectedTab: SettingsTabSelection? = nil) {
        self.selectedTab = selectedTab ?? .shared
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab.tab) {
                GeneralTab()
                    .tabItem { Label("General", systemImage: "gearshape") }
                    .tag(SettingsTab.general)
                LanguagesTab()
                    .tabItem { Label("Languages", systemImage: "globe") }
                    .tag(SettingsTab.languages)
                EnginesTab()
                    .tabItem { Label("Engines", systemImage: "network") }
                    .tag(SettingsTab.engines)
                ShortcutsView()
                    .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                    .tag(SettingsTab.shortcuts)
                AppearanceTab()
                    .tabItem { Label("Appearance", systemImage: "paintbrush") }
                    .tag(SettingsTab.appearance)
                PermissionsTab()
                    .tabItem { Label("Permissions", systemImage: "lock.shield") }
                    .tag(SettingsTab.permissions)
            }

            Divider()
            AboutFooter()
                .padding(.vertical, 10)
        }
        // Tall enough for the Languages tab, whose enabled-language list has
        // to share the height with the Defaults form rather than scrolling
        // with it. Every other tab simply scrolls, so extra height only helps.
        .frame(width: 560, height: 600)
    }
}

/// "Transi <version>", centered — the only chrome the window needs below
/// the tabs.
private struct AboutFooter: View {
    var body: some View {
        Text("Transi \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }
}
