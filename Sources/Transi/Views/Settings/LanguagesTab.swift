import SwiftUI

/// Default source/target/secondary languages, and which languages appear at
/// all in the popup's pickers and the menu bar.
struct LanguagesTab: View {
    @ObservedObject private var settings = SettingsStore.shared
    @State private var query = ""

    /// The default pickers only ever offer enabled languages — this is the
    /// list `enabledLanguageCodes` guarantees a superset of.
    private var enabledLanguages: [LanguageCatalog.Language] {
        settings.enabledLanguages.compactMap { LanguageCatalog.byCode[$0] }
    }

    private var filteredLanguages: [LanguageCatalog.Language] {
        guard !query.isEmpty else { return LanguageCatalog.all }
        let needle = query.lowercased()
        return LanguageCatalog.all.filter {
            $0.englishName.lowercased().contains(needle)
                || $0.nativeName.lowercased().contains(needle)
                || $0.code.lowercased().contains(needle)
        }
    }

    var body: some View {
        Form {
            Section("Defaults") {
                Picker("Default source", selection: $settings.sourceLanguage) {
                    Text("Auto").tag(LanguageCatalog.autoCode)
                    ForEach(enabledLanguages) { lang in
                        Text(lang.displayName).tag(lang.code)
                    }
                }

                Picker("Translate to", selection: $settings.targetLanguage) {
                    ForEach(enabledLanguages) { lang in
                        Text(lang.displayName).tag(lang.code)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Picker("Second language", selection: $settings.secondaryLanguage) {
                        ForEach(enabledLanguages) { lang in
                            Text(lang.displayName).tag(lang.code)
                        }
                    }
                    Text("When text is already in the target language, Transi translates to this instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Enabled Languages") {
                TextField("Search languages", text: $query)

                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredLanguages) { lang in
                            // Target/secondary must stay enabled, so their
                            // toggles are locked on rather than letting the
                            // user strand the default pair.
                            let isDefault = lang.code == settings.targetLanguage
                                || lang.code == settings.secondaryLanguage
                            Toggle(lang.displayName, isOn: enabledBinding(for: lang.code))
                                .disabled(isDefault)
                        }
                    }
                }
                .frame(height: 220)

                Text("The popup's language pickers show only enabled languages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Reads membership through `enabledLanguages` (the target/secondary
    /// superset) so the default pair always shows as "on" even before it has
    /// been explicitly added to the stored `enabledLanguageCodes` list; the
    /// setter still writes that stored list directly.
    private func enabledBinding(for code: String) -> Binding<Bool> {
        Binding(
            get: { settings.enabledLanguages.contains(code) },
            set: { include in
                if include {
                    if !settings.enabledLanguageCodes.contains(code) {
                        settings.enabledLanguageCodes.append(code)
                    }
                } else {
                    settings.enabledLanguageCodes.removeAll { $0 == code }
                }
            }
        )
    }
}
