import Core
import SwiftUI

struct VoiceLanguagesStepView: View {
    @State private var selected: Set<VoiceOnboardingLanguage>
    @State private var autoDetectEverything: Bool
    @State private var statusMessage: String?

    init() {
        let selection = VoiceOnboardingProgressStore.loadLanguageSelection()
        _selected = State(initialValue: Set(selection.selectedLanguages))
        _autoDetectEverything = State(initialValue: selection.autoDetectEverything)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pick languages")
                .font(.title)
                .bold()
            Text("Use Auto-detect for mixed Chinese and English. Single-language choices bias the selected local or cloud recognition engine.")
                .foregroundStyle(.secondary)
            Toggle("Auto-detect language", isOn: $autoDetectEverything)
                .onChange(of: autoDetectEverything) { _, _ in save() }
            ForEach(VoiceOnboardingLanguage.allCases) { language in
                Toggle(language.label, isOn: binding(for: language))
                    .disabled(autoDetectEverything)
                    .opacity(autoDetectEverything ? 0.55 : 1)
            }
            HStack {
                MAYNButton("Apply languages", role: .primary) { save() }
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func binding(for language: VoiceOnboardingLanguage) -> Binding<Bool> {
        Binding {
            selected.contains(language)
        } set: { isOn in
            if isOn {
                selected.insert(language)
            } else {
                selected.remove(language)
            }
        }
    }

    private func save() {
        let selection = VoiceOnboardingLanguageSelection(
            selectedLanguages: Array(selected),
            autoDetectEverything: autoDetectEverything
        )
        VoiceOnboardingProgressStore.saveLanguageSelection(selection)
        var asrSettings = VoiceASRSettingsStore.load()
        asrSettings.languageHint = selection.asrLanguageHint
        VoiceASRSettingsStore.save(asrSettings)
        statusMessage = "Language preference saved as \(VoiceLanguageModePresentation.title(for: selection.asrLanguageHint))."
    }
}
