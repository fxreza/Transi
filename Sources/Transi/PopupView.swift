import SwiftUI

struct PopupView: View {
    @ObservedObject var controller: PopupController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            Divider()

            if let error = controller.errorMessage {
                VStack(spacing: 10) {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                    if let pane = controller.errorSettingsPane {
                        Button(pane.buttonTitle) { pane.open() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                content
            }

            Divider()

            footer
        }
        .padding(12)
        .frame(
            minWidth: Settings.minPopupSize.width, maxWidth: .infinity,
            minHeight: Settings.minPopupSize.height, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(radius: 8)
        )
    }

    private var header: some View {
        HStack {
            Text("Transi")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            if let detected = controller.detectedLanguage {
                Text("\(detected) → \(controller.effectiveTarget.rawValue)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }

            Spacer()

            Button(action: { controller.close() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(controller.sourceText)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: sourceAlignment)
                    .environment(\.layoutDirection, sourceIsRTL ? .rightToLeft : .leftToRight)
                    .textSelection(.enabled)

                if let suggestion = controller.spellingSuggestion {
                    (Text("Did you mean: ").foregroundColor(.secondary)
                        + Text(suggestion).italic())
                        .font(.caption)
                }

                if controller.isCapturing || controller.isLoading || controller.isAILoading
                    || controller.isOCRLoading
                {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(ocrOrTranslationStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text(controller.translatedText)
                        .font(.system(size: 16))
                        .frame(maxWidth: .infinity, alignment: targetAlignment)
                        .environment(\.layoutDirection, targetIsRTL ? .rightToLeft : .leftToRight)
                        .textSelection(.enabled)

                    if !controller.dictionary.isEmpty {
                        dictionarySection
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Picker("", selection: targetBinding) {
                ForEach(TargetLanguage.allCases, id: \.self) { lang in
                    Text(lang == .persian ? "فارسی" : "EN").tag(lang)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 110)

            Spacer()

            if ClaudeAIService.shared.isAvailable {
                Button(action: { controller.aiTranslate() }) {
                    Label("AI", systemImage: "sparkles")
                }
                .help("Translate with Claude (uses your subscription)")
                .disabled(controller.isAILoading || controller.sourceText.isEmpty)
            }

            Button(action: { controller.speak() }) {
                Image(systemName: "speaker.wave.2.fill")
            }
            .help("Read English text aloud")
            .disabled(!controller.canSpeak)

            Button(action: { controller.copyTranslation() }) {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy translation")
            .disabled(controller.translatedText.isEmpty)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    /// Google-Translate-style dictionary: meanings grouped by part of speech,
    /// each with its reverse translations. Shown for single-word lookups.
    private var dictionarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            ForEach(Array(controller.dictionary.enumerated()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.partOfSpeech.capitalized)
                        .font(.caption.bold())
                        .foregroundColor(.accentColor)
                    ForEach(Array(entry.meanings.prefix(6).enumerated()), id: \.offset) { _, meaning in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(meaning.word)
                                .font(.system(size: 13, weight: .medium))
                                .environment(
                                    \.layoutDirection, targetIsRTL ? .rightToLeft : .leftToRight)
                            if !meaning.reverseTranslations.isEmpty {
                                Text(meaning.reverseTranslations.prefix(4).joined(separator: ", "))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var targetBinding: Binding<TargetLanguage> {
        Binding(
            get: { controller.effectiveTarget },
            set: { controller.retranslate(to: $0) }
        )
    }

    private var sourceIsRTL: Bool {
        isRTL(languageCode: controller.detectedLanguage)
    }

    private var targetIsRTL: Bool {
        controller.effectiveTarget == .persian
    }

    private var sourceAlignment: Alignment { sourceIsRTL ? .trailing : .leading }
    private var targetAlignment: Alignment { targetIsRTL ? .trailing : .leading }

    private func isRTL(languageCode: String?) -> Bool {
        guard let code = languageCode?.lowercased() else { return false }
        return ["fa", "ar", "he", "ur", "ps"].contains(where: { code.hasPrefix($0) })
    }

    private var ocrOrTranslationStatus: String {
        if controller.isAILoading { return "Asking Claude…" }
        if controller.isOCRLoading { return "Reading screenshot…" }
        if controller.isCapturing { return "Reading selection…" }
        return "Translating…"
    }
}
