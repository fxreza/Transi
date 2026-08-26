import Foundation
import SwiftUI

/// Startup, update, and a read-only engine summary — full engine
/// configuration lives in the Engines tab; this is a "here's your current
/// setup" pointer, not a duplicate control surface.
struct GeneralTab: View {
    @ObservedObject private var settings = SettingsStore.shared

    @State private var launchAtLoginEnabled = false
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { launchAtLoginEnabled },
                    set: { newValue in
                        launchAtLoginEnabled = newValue
                        if let message = LaunchAtLogin.setEnabled(newValue) {
                            launchAtLoginError = message
                            // The call failed, so reflect what's actually
                            // registered rather than the tap that didn't take.
                            launchAtLoginEnabled = LaunchAtLogin.isEnabled
                        } else {
                            launchAtLoginError = nil
                        }
                    }
                ))
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Updates") {
                Toggle("Include Pre-release Updates", isOn: Binding(
                    get: { settings.includePrereleases },
                    set: { newValue in
                        settings.includePrereleases = newValue
                        if newValue {
                            UpdateService.shared.checkForUpdates(silent: true)
                        }
                    }
                ))

                Button("Check for Updates…") {
                    UpdateService.shared.checkForUpdates(silent: false)
                }
            }

            Section("Engines") {
                Text(settings.orderedEnabledEngines.map(\.displayName).joined(separator: " → "))
                Text("Change order or add Gemini in the Engines tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLoginEnabled = LaunchAtLogin.isEnabled }
    }
}
