import AVFoundation
import Core
import FluidAudio
import Foundation
import Platform
import SwiftUI

struct VoiceSettingsView: View {
    let controller: AppController
    @State private var shortcut: HotkeyDescriptor
    @State private var mode: VoiceActivationMode
    @State private var selectedASRModelID: VoiceASRModelID
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
    @State private var modelDownloadStatus: [VoiceASRModelID: String] = [:]
    @State private var modelDownloadFractions: [VoiceASRModelID: Double] = [:]
    @State private var downloadingModelID: VoiceASRModelID?
    @State private var isShowingDictionary = false
    @State private var microphoneOptions = VoiceMicrophoneOptionDescriptor.available()
    @AppStorage(VoiceAudioSettings.microphoneIDKey, store: AppGroupSettings.defaults) private var preferredMicrophoneID = VoiceAudioSettings.systemMicrophoneID
    @AppStorage("voice.audio.interactionSounds", store: AppGroupSettings.defaults) private var interactionSounds = true
    @AppStorage("voice.audio.muteWhenDictating", store: AppGroupSettings.defaults) private var muteWhenDictating = false
    private let microphoneRefreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init(controller: AppController) {
        self.controller = controller
        let activationSettings = VoiceActivationSettingsStore.load()
        let asrSettings = VoiceASRSettingsStore.load()
        let cleanupSettings = controller.voiceCleanupSettings()
        _shortcut = State(initialValue: activationSettings.shortcut)
        _mode = State(initialValue: activationSettings.mode)
        _selectedASRModelID = State(initialValue: asrSettings.modelID)
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
        .onChange(of: languageHint) { _, hint in
            VoiceASRSettingsStore.save(VoiceASRSettings(modelID: selectedASRModelID, languageHint: hint))
        }
        .onAppear {
            onboardingProgress = VoiceOnboardingProgressStore.load()
            dictionaryEntries = controller.listVoiceDictionaryEntries()
            refreshMicrophoneOptions()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)) { _ in
            refreshMicrophoneOptions()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)) { _ in
            refreshMicrophoneOptions()
        }
        .onReceive(microphoneRefreshTimer) { _ in
            refreshMicrophoneOptions()
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
                    MAYNButton(
                        controller.voiceCoordinator.state == .recording ? "Stop & Paste" : "Start",
                        role: controller.voiceCoordinator.state == .recording ? .secondary : .primary
                    ) {
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
                        MAYNButton(onboardingProgress.isCompleted ? "Open setup" : "Continue setup") {
                            controller.showVoiceOnboarding()
                            onboardingProgress = VoiceOnboardingProgressStore.load()
                        }
                        MAYNButton("Restart") {
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
                    FunctionSegmentedTabStrip(
                        tabs: Array(VoiceActivationMode.allCases),
                        selection: activationModeBinding.wrappedValue,
                        fillsAvailableWidth: false,
                        size: .control
                    ) { mode in
                        activationModeBinding.wrappedValue = mode
                    }
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Shortcut",
                    subtitle: "Global keyboard trigger for voice capture.",
                    minHeight: shortcutIssue == nil ? 46 : 72
                ) {
                    HotkeyRecorderControl(
                        descriptor: activationShortcutBinding,
                        issueMessage: shortcutIssue?.message,
                        defaultDescriptor: VoiceActivationSettings.default.shortcut,
                        recorderWidth: 160,
                        recorderHeight: 26,
                        errorWidth: 230,
                        reset: { applyActivationShortcut(VoiceActivationSettings.default.shortcut) }
                    )
                }

                if let errorMessage {
                    MAYNDivider()
                    MAYNSettingsRow(title: "Voice error") {
                        StatusPill(text: errorMessage, kind: .danger)
                    }
                }
            }

            MAYNSection(
                title: "Recognition model",
                subtitle: "Choose from supported local ASR models. Missing models download before use."
            ) {
                ForEach(Array(VoiceASRModelID.allCases.enumerated()), id: \.element.id) { index, modelID in
                    if index > 0 { MAYNDivider() }
                    VoiceSettingsModelRow(
                        modelID: modelID,
                        isSelected: selectedASRModelID == modelID,
                        isDownloaded: isDownloaded(modelID),
                        isDownloading: downloadingModelID == modelID,
                        statusMessage: modelDownloadStatus[modelID],
                        downloadFraction: modelDownloadFractions[modelID],
                        action: { selectModel(modelID) }
                    )
                }
            }

            MAYNSection(title: "Language") {
                MAYNSettingsRow(
                    title: "Dictation language",
                    subtitle: "Choose how dictation biases recognition. Auto-detect is best for mixed Chinese and English; switch to one language only when results drift."
                ) {
                    MAYNDropdown(
                        selection: $languageHint,
                        options: Array(VoiceASRLanguageHint.allCases),
                        title: VoiceLanguageModePresentation.title,
                        width: MAYNControlMetrics.widePickerWidth
                    )
                }
            }

            MAYNSection(title: "Audio") {
                MAYNSettingsRow(
                    title: "Microphone",
                    subtitle: "Choose the preferred input device for voice capture. Auto follows macOS Sound settings."
                ) {
                    MAYNDropdown(
                        selection: $preferredMicrophoneID,
                        options: microphoneOptions.map(\.id),
                        title: microphoneTitle,
                        width: MAYNControlMetrics.widePickerWidth
                    )
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
                    MAYNDropdown(
                        selection: $cleanupProvider,
                        options: Array(VoiceCleanupProviderKind.allCases),
                        title: { $0.label }
                    )
                }
            MAYNDivider()
            MAYNSettingsRow(title: "Model") {
                MAYNTextField(text: $cleanupModel)
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Base URL") {
                MAYNTextField(text: $cleanupBaseURLString)
            }
            MAYNDivider()
            MAYNSettingsRow(title: "API key") {
                MAYNSecureField(text: $cleanupAPIKey)
            }
                MAYNDivider()
                MAYNSettingsRow(title: "Timeout") {
                    MAYNNumericStepper(
                        text: "\(cleanupTimeoutSeconds)s",
                        value: $cleanupTimeoutSeconds,
                        range: 1...30,
                        presets: [3, 5, 7, 10, 15, 30],
                        suffix: "s"
                    )
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Cleanup actions") {
                    HStack(spacing: 8) {
                        MAYNButton("Test") { testCleanupSettings() }
                        MAYNButton("Apply", role: .primary) { applyCleanupSettings() }
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
                    MAYNButton("Open") {
                        dictionaryEntries = controller.listVoiceDictionaryEntries()
                        isShowingDictionary = true
                    }
                }
            }

            // App-specific overrides are now configured in the Personalization tab.

            MAYNSection(title: "History / MVP") {
                MAYNSettingsRow(title: "Default shortcut") {
                    ShortcutChip(text: VoiceActivationSettings.default.shortcut.display)
                }
                MAYNDivider()
                MAYNSettingsRow(title: "ASR") {
                    StatusPill(text: selectedASRModelID.title, kind: .neutral)
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

    private var activationShortcutBinding: Binding<HotkeyDescriptor> {
        Binding(
            get: { shortcut },
            set: { descriptor in
                applyActivationShortcut(descriptor)
            }
        )
    }

    private var activationModeBinding: Binding<VoiceActivationMode> {
        Binding(
            get: { mode },
            set: { newMode in
                mode = newMode
                applyActivationSettingsIfValid()
            }
        )
    }

    private func applyActivationShortcut(_ descriptor: HotkeyDescriptor) {
        shortcut = descriptor
        applyActivationSettingsIfValid()
    }

    private func applyActivationSettingsIfValid() {
        if let shortcutIssue {
            errorMessage = shortcutIssue.message
            return
        }

        do {
            try controller.applyVoiceActivationSettings(VoiceActivationSettings(shortcut: shortcut, mode: mode))
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

    private func selectModel(_ modelID: VoiceASRModelID) {
        if isDownloaded(modelID) {
            useModel(modelID)
        } else {
            downloadModel(modelID, selectWhenReady: true)
        }
    }

    private func useModel(_ modelID: VoiceASRModelID) {
        selectedASRModelID = modelID
        VoiceASRSettingsStore.save(VoiceASRSettings(modelID: modelID, languageHint: languageHint))
        modelDownloadStatus[modelID] = "Selected for future dictation."
    }

    private func downloadModel(_ modelID: VoiceASRModelID, selectWhenReady: Bool = false) {
        guard downloadingModelID == nil else { return }
        guard #available(macOS 15, *) else {
            modelDownloadStatus[modelID] = "Requires macOS 15 or later."
            return
        }

        downloadingModelID = modelID
        modelDownloadFractions[modelID] = 0
        modelDownloadStatus[modelID] = "Preparing download..."
        Task {
            do {
                try await Qwen3AsrModels.download(
                    variant: modelID.variant,
                    progressHandler: { progress in
                        Task { @MainActor in
                            modelDownloadStatus[modelID] = VoiceSettingsModelDownloadPresenter.describe(progress)
                            modelDownloadFractions[modelID] = progress.fractionCompleted
                        }
                    }
                )
                await MainActor.run {
                    downloadingModelID = nil
                    modelDownloadFractions[modelID] = nil
                    modelDownloadStatus[modelID] = "Downloaded."
                    if selectWhenReady {
                        useModel(modelID)
                    }
                }
            } catch {
                await MainActor.run {
                    downloadingModelID = nil
                    modelDownloadFractions[modelID] = nil
                    modelDownloadStatus[modelID] = error.localizedDescription
                }
            }
        }
    }

    private func isDownloaded(_ modelID: VoiceASRModelID) -> Bool {
        guard #available(macOS 15, *) else { return false }
        return Qwen3AsrModels.modelsExist(
            at: Qwen3AsrModels.defaultCacheDirectory(variant: modelID.variant)
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

    private func refreshMicrophoneOptions() {
        let options = VoiceMicrophoneOptionDescriptor.available()
        microphoneOptions = options
        let normalized = VoiceAudioSettings.normalizedPreferredMicrophoneID(
            preferredMicrophoneID,
            availableDeviceIDs: Set(options.map(\.id))
        )
        if normalized != preferredMicrophoneID {
            preferredMicrophoneID = normalized
        }
    }

    private func microphoneTitle(_ id: String) -> String {
        microphoneOptions.first { $0.id == id }?.name ?? "Auto-detect"
    }
}

enum VoiceLanguageModePresentation {
    static let exposesSingleDropdown = true
    static let showsSeparateMultipleLanguagesStatus = false

    static func title(for hint: VoiceASRLanguageHint) -> String {
        switch hint {
        case .automatic:
            "Auto-detect Chinese + English"
        case .chinese:
            "Chinese only"
        case .english:
            "English only"
        }
    }
}

private struct VoiceSettingsModelRow: View {
    let modelID: VoiceASRModelID
    let isSelected: Bool
    let isDownloaded: Bool
    let isDownloading: Bool
    let statusMessage: String?
    let downloadFraction: Double?
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: MAYNControlMetrics.rowControlSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                VoiceASRModelTitleLine(modelID: modelID)
                Text(modelID.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 8) {
                if let statusText = presentation.statusText {
                    StatusPill(text: statusText, kind: presentation.statusKind.statusPillKind)
                }
                if let downloadFraction {
                    ProgressView(value: downloadFraction)
                        .frame(width: 170)
                }
                if let actionTitle = presentation.actionTitle {
                    MAYNButton(actionTitle, action: action)
                }
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: MAYNControlMetrics.trailingLaneMinWidth, alignment: .trailing)
        }
        .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
        .padding(.vertical, MAYNControlMetrics.rowVerticalPadding)
        .frame(minHeight: downloadFraction == nil ? 96 : 114)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovering ? MAYNTheme.hover : Color.clear)
        .contentShape(Rectangle())
        .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isHovering)
        .onHover { isHovering = $0 }
    }

    private var presentation: VoiceASRModelRowPresentation {
        VoiceASRModelRowPresentation.model(
            isSelected: isSelected,
            isDownloaded: isDownloaded,
            isDownloading: isDownloading
        )
    }
}

struct VoiceASRModelTitleLine: View {
    let modelID: VoiceASRModelID

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            Text(VoiceASRModelTitlePresentation.title(for: modelID))
                .font(.callout)
            VoiceASRModelSizeTag(text: VoiceASRModelTitlePresentation.sizeLabel(for: modelID))
        }
    }
}

private struct VoiceASRModelSizeTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(MAYNTheme.elevated, in: Capsule())
            .overlay(Capsule().stroke(MAYNTheme.subtleBorder, lineWidth: 1))
    }
}

private enum VoiceSettingsModelDownloadPresenter {
    static func describe(_ progress: DownloadUtils.DownloadProgress) -> String {
        switch progress.phase {
        case .listing:
            "Listing model files..."
        case let .downloading(completedFiles, totalFiles):
            "Downloading \(completedFiles)/\(totalFiles) files..."
        case let .compiling(modelName):
            "Compiling \(modelName)..."
        }
    }
}
