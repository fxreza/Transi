import SwiftUI

/// Accent color, light/dark mode, popup text size, and popup window sizing.
struct AppearanceTab: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        Form {
            Section("Theme") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Accent color")
                    accentPicker
                }
                .padding(.vertical, 2)

                Picker("Appearance", selection: $settings.colorScheme) {
                    ForEach(AppColorScheme.allCases) { scheme in
                        Text(scheme.label).tag(scheme)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Popup Text Size") {
                Slider(value: $settings.popupTextSize, in: 0.8...1.6)
                Text("Sample translation")
                    .font(.system(size: 16 * settings.popupTextSize))
            }

            Section("Popup Window") {
                Toggle("Larger buttons and controls", isOn: $settings.largePopupControls)
                Text("Enlarges the language pickers, swap, pin, and the icons on result cards — without changing the text size above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Close automatically when the mouse moves away", isOn: $settings.autoDismissEnabled)
                if settings.autoDismissEnabled {
                    HStack {
                        Slider(value: $settings.autoDismissDelay, in: 0.5...10, step: 0.5) {
                            Text("Delay")
                        }
                        Text(String(format: "%.1f s", settings.autoDismissDelay))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                    Text("A pinned popup, an open language picker, or unsent typed text keep the window open regardless.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Reset Popup Size") { settings.resetPopupSize() }
            }
        }
        .formStyle(.grouped)
    }

    /// A row of tappable swatches with a ring on the selected one;
    /// `.system` shows a half-fill glyph since it has no single color of its
    /// own (it follows the macOS accent color).
    private var accentPicker: some View {
        HStack(spacing: 10) {
            ForEach(AccentTheme.allCases) { theme in
                let selected = settings.accentTheme == theme
                Button {
                    settings.accentTheme = theme
                } label: {
                    ZStack {
                        Circle()
                            .fill(theme == .system ? Color.gray : theme.color)
                            .frame(width: 22, height: 22)
                        if theme == .system {
                            Image(systemName: "circle.lefthalf.filled")
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                        if selected {
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.85), lineWidth: 2)
                                .frame(width: 28, height: 28)
                        }
                    }
                    .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .help(theme.label)
            }
        }
    }
}
