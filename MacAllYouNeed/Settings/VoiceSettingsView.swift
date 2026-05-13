import AVFoundation
import Core
import Platform
import SwiftUI

struct VoiceSettingsView: View {
    let controller: AppController
    @State private var shortcut: HotkeyDescriptor
    @State private var mode: VoiceActivationMode
    @State private var languageHint: VoiceASRLanguageHint
    @State private var dictionaryEntries: [VoiceDictionaryEntry]
    @State private var cleanupEnabled: Bool
    @State private var cleanupProvider: VoiceCleanupProviderKind
    @State private var cleanupModel: String
    @State private var cleanupBaseURLString: String
    @State private var cleanupAPIKey: String
    @State private var cleanupTimeoutSeconds: Int
    @State private var cleanupStatusMessage: String?
    @State private var onboardingProgress: VoiceOnboardingProgress
    @State private var errorMessage: String?
    @State private var isShowingDictionary = false
    @State private var microphoneOptions = VoiceMicrophoneOption.available()
    @AppStorage(VoiceAudioSettings.microphoneIDKey, store: AppGroupSettings.defaults) private var preferredMicrophoneID = VoiceAudioSettings.systemMicrophoneID
    @AppStorage("voice.audio.interactionSounds", store: AppGroupSettings.defaults) private var interactionSounds = true
    @AppStorage("voice.audio.muteWhenDictating", store: AppGroupSettings.defaults) private var muteWhenDictating = false

    init(controller: AppController) {
        self.controller = controller
        let activationSettings = VoiceActivationSettingsStore.load()
        let asrSettings = VoiceASRSettingsStore.load()
        let cleanupSettings = controller.voiceCleanupSettings()
        _shortcut = State(initialValue: activationSettings.shortcut)
        _mode = State(initialValue: activationSettings.mode)
        _languageHint = State(initialValue: asrSettings.languageHint)
        _dictionaryEntries = State(initialValue: controller.listVoiceDictionaryEntries())
        _cleanupEnabled = State(initialValue: cleanupSettings.isEnabled)
        _cleanupProvider = State(initialValue: cleanupSettings.provider)
        _cleanupModel = State(initialValue: cleanupSettings.model)
        _cleanupBaseURLString = State(initialValue: cleanupSettings.baseURLString)
        _cleanupAPIKey = State(initialValue: controller.voiceCleanupAPIKey(for: cleanupSettings.provider))
        _cleanupTimeoutSeconds = State(initialValue: cleanupSettings.timeoutSeconds)
        _onboardingProgress = State(initialValue: VoiceOnboardingProgressStore.load())
    }

    var body: some View {
        Group {
            if isShowingDictionary {
                VoiceDictionaryPage(controller: controller) {
                    dictionaryEntries = controller.listVoiceDictionaryEntries()
                    isShowingDictionary = false
                }
            } else {
                mainContent
            }
        }
        .onChange(of: cleanupProvider) { _, provider in
            cleanupModel = provider.defaultModel
            cleanupBaseURLString = provider.defaultBaseURLString
            cleanupAPIKey = controller.voiceCleanupAPIKey(for: provider)
        }
        .onAppear {
            onboardingProgress = VoiceOnboardingProgressStore.load()
            dictionaryEntries = controller.listVoiceDictionaryEntries()
            microphoneOptions = VoiceMicrophoneOption.available()
        }
    }

    private var mainContent: some View {
        MAYNSettingsPage(
            title: "Voice",
            subtitle: "Configure dictation setup, activation, recognition, cleanup, and app-specific behavior."
        ) {
            MAYNSection(title: "Overview") {
                MAYNSettingsRow(
                    title: "Dictation",
                    subtitle: voiceStateTitle
                ) {
                    Button(controller.voiceCoordinator.state == .recording ? "Stop & Paste" : "Start") {
                        if controller.voiceCoordinator.state == .recording {
                            Task { await controller.voiceCoordinator.stopRecordingAndPaste() }
                        } else {
                            Task { await controller.voiceCoordinator.startRecording() }
                        }
                    }
                    .disabled(!canToggleVoice)
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Last transcript",
                    subtitle: lastTranscriptText
                ) {
                    StatusPill(text: controller.voiceCoordinator.lastTranscript?.usedLLM == true ? "LLM" : "Local", kind: .neutral)
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Voice onboarding",
                    subtitle: "Checks microphone, Accessibility, ASR, cleanup, shortcut, languages, and a try-it pass."
                ) {
                    StatusPill(
                        text: onboardingProgress.isCompleted ? "Completed" : onboardingProgress.currentStep.title,
                        kind: onboardingProgress.isCompleted ? .success : .progress
                    )
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Setup actions") {
                    HStack(spacing: 8) {
                        Button(onboardingProgress.isCompleted ? "Open setup" : "Continue setup") {
                            controller.showVoiceOnboarding()
                            onboardingProgress = VoiceOnboardingProgressStore.load()
                        }
                        Button("Restart") {
                            controller.restartVoiceOnboarding()
                            onboardingProgress = VoiceOnboardingProgressStore.load()
                        }
                    }
                }
            }

            MAYNSection(title: "Activation") {
                MAYNSettingsRow(
                    title: "Mode",
                    subtitle: "Toggle starts on first press and stops on second press. Hold records while the shortcut is held."
                ) {
                    Picker("", selection: $mode) {
                        ForEach(VoiceActivationMode.allCases) { mode in
                            Text(mode.compactLabel).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Shortcut",
                    subtitle: "Global keyboard trigger for voice capture.",
                    minHeight: shortcutIssue == nil ? 46 : 72
                ) {
                    VStack(alignment: .leading, spacing: 5) {
                        HotkeyRecorder(descriptor: $shortcut, isInvalid: shortcutIssue != nil)
                            .frame(width: 160, height: 26)
                        if let shortcutIssue {
                            Text(shortcutIssue.message)
                                .font(.caption)
                                .foregroundStyle(MAYNTheme.danger)
                                .frame(width: 210, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Apply activation",
                    subtitle: "Save activation and recognition language settings together."
                ) {
                    Button("Apply") { apply() }
                        .disabled(shortcutIssue != nil)
                }

                if let errorMessage {
                    MAYNDivider()
                    MAYNSettingsRow(title: "Voice error") {
                        StatusPill(text: errorMessage, kind: .danger)
                    }
                }
            }

            MAYNSection(title: "Language") {
                MAYNSettingsRow(
                    title: "Dictation language",
                    subtitle: "Use Auto for mixed Chinese and English. Pick one language only when the transcript is consistently biased wrong."
                ) {
                    Picker("", selection: $languageHint) {
                        ForEach(VoiceASRLanguageHint.allCases) { hint in
                            Text(hint.label).tag(hint)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 180)
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Multiple languages",
                    subtitle: "The ASR engine accepts one hint per pass; Auto is the supported mixed-language mode for now."
                ) {
                    StatusPill(text: "Auto", kind: .neutral)
                }
            }

            MAYNSection(title: "Audio") {
                MAYNSettingsRow(
                    title: "Microphone",
                    subtitle: "Choose the preferred input device for voice capture. Auto follows macOS Sound settings."
                ) {
                    Picker("", selection: $preferredMicrophoneID) {
                        ForEach(microphoneOptions) { option in
                            Text(option.name).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 210)
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Interaction sounds",
                    subtitle: "Reserved for voice start/stop feedback."
                ) {
                    Toggle("", isOn: $interactionSounds)
                        .labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Mute when dictating",
                    subtitle: "Preference only; automatic app audio ducking is not wired yet."
                ) {
                    Toggle("", isOn: $muteWhenDictating)
                        .labelsHidden()
                }
            }

            MAYNSection(title: "Cleanup") {
                MAYNSettingsRow(
                    title: "AI cleanup",
                    subtitle: "Send recognized text through the configured cleanup provider before paste."
                ) {
                    Toggle("", isOn: $cleanupEnabled)
                        .labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Provider") {
                    Picker("", selection: $cleanupProvider) {
                        ForEach(VoiceCleanupProviderKind.allCases) { provider in
                            Text(provider.label).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Model") {
                    TextField("", text: $cleanupModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Base URL") {
                    TextField("", text: $cleanupBaseURLString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                }
                MAYNDivider()
                MAYNSettingsRow(title: "API key") {
                    SecureField("", text: $cleanupAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Timeout") {
                    MAYNNumericStepper(
                        text: "\(cleanupTimeoutSeconds)s",
                        value: $cleanupTimeoutSeconds,
                        range: 1...30
                    )
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Cleanup actions") {
                    HStack(spacing: 8) {
                        Button("Test") { testCleanupSettings() }
                        Button("Apply") { applyCleanupSettings() }
                    }
                }

                if let cleanupStatusMessage {
                    MAYNDivider()
                    MAYNSettingsRow(title: "Cleanup status") {
                        StatusPill(text: cleanupStatusMessage, kind: .neutral)
                    }
                }
            }

            MAYNSection(title: "Dictionary") {
                MAYNSettingsRow(
                    title: "Voice dictionary",
                    subtitle: "\(dictionaryEntries.count) manual entries. Correct names, product terms, and recurring ASR mistakes before cleanup and paste."
                ) {
                    Button("Open") {
                        dictionaryEntries = controller.listVoiceDictionaryEntries()
                        isShowingDictionary = true
                    }
                }
            }

            VoiceAppProfilesSection(controller: controller, errorMessage: $errorMessage)

            MAYNSection(title: "History / MVP") {
                MAYNSettingsRow(title: "Default shortcut") {
                    ShortcutChip(text: VoiceActivationSettings.default.shortcut.display)
                }
                MAYNDivider()
                MAYNSettingsRow(title: "ASR") {
                    StatusPill(text: "Qwen3-ASR f32", kind: .neutral)
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Language hint") {
                    StatusPill(text: VoiceASRSettings.default.languageHint.label, kind: .neutral)
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Paste",
                    subtitle: "If paste does not occur, grant Accessibility and press Command-V manually."
                ) {
                    StatusPill(text: "Accessibility + Command-V", kind: .neutral)
                }
            }
        }
    }

    private func apply() {
        if let shortcutIssue {
            errorMessage = shortcutIssue.message
            return
        }

        do {
            try controller.applyVoiceActivationSettings(VoiceActivationSettings(shortcut: shortcut, mode: mode))
            VoiceASRSettingsStore.save(VoiceASRSettings(languageHint: languageHint))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyCleanupSettings() {
        do {
            try controller.applyVoiceCleanupSettings(cleanupSettingsDraft, apiKey: cleanupAPIKey)
            cleanupStatusMessage = "Cleanup settings saved."
            errorMessage = nil
        } catch {
            cleanupStatusMessage = error.localizedDescription
        }
    }

    private func testCleanupSettings() {
        cleanupStatusMessage = controller.validateVoiceCleanupSettings(
            cleanupSettingsDraft,
            apiKey: cleanupAPIKey
        )
    }

    private var canToggleVoice: Bool {
        switch controller.voiceCoordinator.state {
        case .idle, .recording:
            true
        case .transcribing, .pasting, .error:
            false
        }
    }

    private var shortcutIssue: HotkeyValidationIssue? {
        HotkeyValidation.issue(forVoiceShortcut: shortcut, appHotkeys: HotkeyMapStore.load())
    }

    private var voiceStateTitle: String {
        switch controller.voiceCoordinator.state {
        case .idle:
            "Ready for local dictation."
        case .recording:
            "Listening. Stop to transcribe and paste."
        case .transcribing:
            "Transcribing audio."
        case .pasting:
            "Pasting into the focused app."
        case let .error(message):
            message
        }
    }

    private var lastTranscriptText: String {
        guard let transcript = controller.voiceCoordinator.lastTranscript else {
            return "No transcript captured yet."
        }
        let text = transcript.cleanedText.isEmpty ? transcript.rawText : transcript.cleanedText
        return text.isEmpty ? "Last transcript is empty." : text
    }

    private var cleanupSettingsDraft: VoiceCleanupSettings {
        VoiceCleanupSettings(
            isEnabled: cleanupEnabled,
            provider: cleanupProvider,
            model: cleanupModel,
            baseURLString: cleanupBaseURLString,
            timeoutSeconds: cleanupTimeoutSeconds
        )
    }

}

private struct VoiceMicrophoneOption: Identifiable, Equatable {
    static let systemID = VoiceAudioSettings.systemMicrophoneID

    let id: String
    let name: String

    static func available() -> [VoiceMicrophoneOption] {
        let system = VoiceMicrophoneOption(id: systemID, name: "Auto-detect (System input)")
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        let devices = session.devices.map {
            VoiceMicrophoneOption(id: $0.uniqueID, name: $0.localizedName)
        }
        return [system] + devices
    }
}

private extension VoiceActivationMode {
    var compactLabel: String {
        switch self {
        case .toggle:
            "Toggle"
        case .hold:
            "Hold"
        }
    }
}
