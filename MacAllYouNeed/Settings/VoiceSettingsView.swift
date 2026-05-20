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
    @State private var asrProviderKind: VoiceASRProviderKind
    @State private var cloudModelID: VoiceCloudASRModelID
    @State private var cloudLanguageHint: VoiceASRLanguageHint
    @State private var cloudAPIKeys: [VoiceASRProviderKind: String]
    @State private var cloudSetupProviderKind: VoiceASRProviderKind
    @State private var cloudStatusMessage: String?
    @State private var isTestingCloud = false
    @State private var dictionaryEntries: [VoiceDictionaryEntry]
    @State private var cleanupEnabled: Bool
    @State private var cleanupProvider: VoiceCleanupProviderKind
    @State private var cleanupModel: String
    @State private var cleanupBaseURLString: String
    @State private var cleanupAPIKey: String
    @State private var cleanupTimeoutSeconds: Int
    @State private var cleanupLatencyPolicy: VoiceCleanupLatencyPolicy
    @State private var cleanupStatusMessage: String?
    @State private var onboardingProgress: VoiceOnboardingProgress
    @State private var errorMessage: String?
    @State private var modelDownloadStatus: [VoiceASRModelID: String] = [:]
    @State private var modelDownloadFractions: [VoiceASRModelID: Double] = [:]
    @State private var downloadingModelID: VoiceASRModelID?
    @State private var isShowingDictionary = false
    @State private var showsCacheCleanupSheet = false
    @State private var microphoneOptions = VoiceMicrophoneOptionDescriptor.available()
    @AppStorage(VoiceAudioSettings.microphoneIDKey, store: AppGroupSettings.defaults) private var preferredMicrophoneID = VoiceAudioSettings
        .systemMicrophoneID
    @AppStorage("voice.audio.interactionSounds", store: AppGroupSettings.defaults) private var interactionSounds = true
    @AppStorage("voice.audio.muteWhenDictating", store: AppGroupSettings.defaults) private var muteWhenDictating = false
    @AppStorage("voice.asr.groq.apiSetupExpanded", store: AppGroupSettings.defaults) private var isCloudAPISetupExpanded = false
    private let microphoneRefreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init(controller: AppController) {
        self.controller = controller
        let activationSettings = VoiceActivationSettingsStore.load()
        let asrSettings = VoiceASRSettingsStore.load()
        let cloudSettings = VoiceCloudASRSettingsStore.load()
        let cleanupSettings = controller.voiceCleanupSettings()
        _shortcut = State(initialValue: activationSettings.shortcut)
        _mode = State(initialValue: activationSettings.mode)
        _selectedASRModelID = State(initialValue: asrSettings.modelID)
        _languageHint = State(initialValue: asrSettings.languageHint)
        _asrProviderKind = State(initialValue: asrSettings.providerKind)
        _cloudModelID = State(
            initialValue: asrSettings.providerKind.isCloud
                ? cloudSettings.modelID(for: asrSettings.providerKind)
                : cloudSettings.modelID
        )
        _cloudLanguageHint = State(initialValue: cloudSettings.languageHint)
        let cloudKeys = Dictionary(
            uniqueKeysWithValues: VoiceASRProviderKind.allCases
                .filter(\.isCloud)
                .map { ($0, controller.cloudASRAPIKey(for: $0)) }
        )
        _cloudAPIKeys = State(initialValue: cloudKeys)
        _cloudSetupProviderKind = State(initialValue: asrSettings.providerKind.isCloud ? asrSettings.providerKind : cloudSettings.modelID.providerKind)
        _dictionaryEntries = State(initialValue: controller.listVoiceDictionaryEntries())
        _cleanupEnabled = State(initialValue: cleanupSettings.isEnabled)
        _cleanupProvider = State(initialValue: cleanupSettings.provider)
        _cleanupModel = State(initialValue: cleanupSettings.model)
        _cleanupBaseURLString = State(initialValue: cleanupSettings.baseURLString)
        _cleanupAPIKey = State(initialValue: controller.voiceCleanupAPIKey(for: cleanupSettings.provider))
        _cleanupTimeoutSeconds = State(initialValue: cleanupSettings.timeoutSeconds)
        _cleanupLatencyPolicy = State(initialValue: cleanupSettings.latencyPolicy)
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
            controller.applyVoiceASRSettings(currentAppliedASRSettings.updating(languageHint: hint))
        }
        .onChange(of: asrProviderKind) { _, providerKind in
            applyASRProviderSelection(providerKind)
        }
        .onChange(of: cloudModelID) { _, newModelID in
            cloudSetupProviderKind = newModelID.providerKind
            applyCloudDropdownSettings()
        }
        .onChange(of: cloudLanguageHint) { _, _ in
            applyCloudDropdownSettings()
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
                        candidateIssueMessage: { shortcutCandidateIssue($0)?.message },
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

            MAYNSection(title: "Models") {
                MAYNSettingsRow(
                    title: "Recognition model",
                    subtitle: recognitionModelSummary
                ) {
                    MAYNButton("Open Models") {
                        controller.showVoiceModels()
                    }
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Cleanup model",
                    subtitle: cleanupModelSummary
                ) {
                    StatusPill(text: cleanupEnabled ? cleanupProvider.label : "Off", kind: .neutral)
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
            MAYNSection(title: "Storage") {
                MAYNSettingsRow(
                    title: "Cached model files",
                    subtitle: "Reclaim disk space without removing the Voice feature."
                ) {
                    MAYNButton("Clear cached models…") {
                        showsCacheCleanupSheet = true
                    }
                }
            }
        }
        .sheet(isPresented: $showsCacheCleanupSheet) {
            VoiceCacheCleanupSheet(
                descriptor: VoiceDescriptor.descriptor(),
                onClose: { showsCacheCleanupSheet = false }
            )
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

    private func applyASRProviderSelection(_ providerKind: VoiceASRProviderKind) {
        switch providerKind {
        case .local:
            controller.applyVoiceASRSettings(providerASRSettingsDraft)
            cloudStatusMessage = nil
            errorMessage = nil
        case .groq, .elevenLabs, .openAITranscribe, .deepgram:
            cloudSetupProviderKind = providerKind
            cloudModelID = cloudASRSettingsDraft.modelID(for: providerKind)
            guard hasUsableCloudAPIKey(for: providerKind) else {
                isCloudAPISetupExpanded = true
                cloudStatusMessage = "Add \(providerKind.apiKeyLabel) before dictating with \(providerKind.label)."
                return
            }
            controller.applyCloudASRSettings(cloudASRSettingsDraft)
            controller.applyVoiceASRSettings(providerASRSettingsDraft)
            applyCloudProviderSettings(successMessage: "\(providerKind.label) selected.")
        }
    }

    private func applyCloudDropdownSettings() {
        controller.applyCloudASRSettings(cloudASRSettingsDraft)
        if asrProviderKind == cloudModelID.providerKind {
            applyASRProviderSelection(cloudModelID.providerKind)
        }
    }

    private func applyCloudProviderSettings(successMessage: String) {
        do {
            try controller.applyVoiceASRProviderSettings(
                asrSettings: providerASRSettingsDraft,
                cloudSettings: cloudASRSettingsDraft,
                cloudAPIKey: cloudAPIKeys[cloudSetupProviderKind] ?? ""
            )
            cloudStatusMessage = successMessage
            errorMessage = nil
        } catch {
            let message = error.localizedDescription
            cloudStatusMessage = message
            errorMessage = message
        }
    }

    private func testCloudConnection() {
        isTestingCloud = true
        cloudStatusMessage = "Connecting..."
        let settings = cloudASRSettingsDraft.updating(modelID: cloudASRSettingsDraft.modelID(for: cloudSetupProviderKind))
        let providerKind = cloudSetupProviderKind
        let key = cloudAPIKeys[providerKind] ?? ""
        Task {
            let result = await controller.testCloudASRSettings(settings, providerKind: providerKind, apiKey: key)
            await MainActor.run {
                if result.localizedCaseInsensitiveContains("succeeded") {
                    cloudModelID = settings.modelID
                    asrProviderKind = providerKind
                    applyCloudProviderSettings(successMessage: "Connection succeeded. Future dictations will use \(providerKind.label).")
                } else {
                    cloudStatusMessage = result
                }
                isTestingCloud = false
            }
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

    private func selectCloudModel(_ modelID: VoiceCloudASRModelID) {
        cloudSetupProviderKind = modelID.providerKind
        guard hasUsableCloudAPIKey(for: modelID.providerKind) else {
            isCloudAPISetupExpanded = true
            cloudStatusMessage = "Add \(modelID.providerKind.apiKeyLabel) before selecting this cloud model."
            return
        }

        cloudModelID = modelID
        let providerKind = VoiceASRModelSelectionState.providerKindAfterSelectingCloudModel(modelID)
        asrProviderKind = providerKind
        applyASRProviderSelection(providerKind)
    }

    private func useModel(_ modelID: VoiceASRModelID) {
        selectedASRModelID = modelID
        let providerKind = VoiceASRModelSelectionState.providerKindAfterSelectingLocalModel()
        asrProviderKind = providerKind
        controller.applyVoiceASRSettings(
            VoiceASRSettings(
                modelID: modelID,
                languageHint: languageHint,
                providerKind: providerKind
            )
        )
        modelDownloadStatus[modelID] = "Selected for future dictation."
    }

    private func downloadModel(_ modelID: VoiceASRModelID, selectWhenReady: Bool = false) {
        guard downloadingModelID == nil else { return }

        downloadingModelID = modelID
        modelDownloadFractions[modelID] = 0
        modelDownloadStatus[modelID] = "Preparing download..."
        Task {
            do {
                try await VoiceModelManager.downloadLocalASRModel(
                    modelID,
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

    private func showModelInFinder(_ modelID: VoiceASRModelID) {
        VoiceModelManager.showLocalASRModelInFinder(modelID)
    }

    private func deleteModel(_ modelID: VoiceASRModelID) {
        do {
            try VoiceModelManager.deleteLocalASRModel(modelID)
            let installed = VoiceModelManager.installedLocalASRModelIDs()
            if let fallback = VoiceModelManager.fallbackLocalASRModel(
                afterDeleting: modelID,
                selectedModelID: selectedASRModelID,
                installedModelIDsAfterDelete: installed
            ), fallback != selectedASRModelID {
                useModel(fallback)
                modelDownloadStatus[fallback] = "Selected because the previous model was deleted."
            }
            modelDownloadStatus[modelID] = "Deleted."
        } catch {
            modelDownloadStatus[modelID] = error.localizedDescription
        }
    }

    private func isDownloaded(_ modelID: VoiceASRModelID) -> Bool {
        VoiceModelManager.isLocalASRModelInstalled(modelID)
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

    private func shortcutCandidateIssue(_ descriptor: HotkeyDescriptor) -> HotkeyValidationIssue? {
        HotkeyValidation.issue(forVoiceShortcut: descriptor, appHotkeys: HotkeyMapStore.load())
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

    private var recognitionModelSummary: String {
        switch asrProviderKind {
        case .local:
            selectedASRModelID.title
        case .groq, .elevenLabs, .openAITranscribe, .deepgram:
            cloudModelID.title
        }
    }

    private var cleanupModelSummary: String {
        guard cleanupEnabled else {
            return "AI cleanup is off; local cleanup and dictionary still apply."
        }
        let model = cleanupModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? cleanupProvider.label : "\(cleanupProvider.label) · \(model)"
    }

    private var cleanupSettingsDraft: VoiceCleanupSettings {
        VoiceCleanupSettings(
            isEnabled: cleanupEnabled,
            provider: cleanupProvider,
            model: cleanupModel,
            baseURLString: cleanupBaseURLString,
            timeoutSeconds: cleanupTimeoutSeconds,
            latencyPolicy: cleanupLatencyPolicy
        )
    }

    private var currentAppliedASRSettings: VoiceASRSettings {
        VoiceASRSettings(
            modelID: selectedASRModelID,
            languageHint: languageHint,
            providerKind: VoiceASRSettingsStore.load().providerKind
        )
    }

    private var providerASRSettingsDraft: VoiceASRSettings {
        VoiceASRSettings(
            modelID: selectedASRModelID,
            languageHint: languageHint,
            providerKind: asrProviderKind
        )
    }

    private var cloudASRSettingsDraft: VoiceCloudASRSettings {
        VoiceCloudASRSettings(modelID: cloudModelID, languageHint: cloudLanguageHint)
    }

    private var cloudAPIKeyBinding: Binding<String> {
        Binding(
            get: { cloudAPIKeys[cloudSetupProviderKind] ?? "" },
            set: { cloudAPIKeys[cloudSetupProviderKind] = $0 }
        )
    }

    private func hasUsableCloudAPIKey(for providerKind: VoiceASRProviderKind) -> Bool {
        VoiceASRModelSelectionState.canSelectCloudModel(apiKey: cloudAPIKeys[providerKind] ?? "")
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

struct VoiceCloudASRModelRow: View {
    let modelID: VoiceCloudASRModelID
    let isSelected: Bool
    let hasUsableAPIKey: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: MAYNControlMetrics.rowControlSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Text(modelID.title)
                    .font(.callout)
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
                if let actionTitle = presentation.actionTitle {
                    MAYNButton(actionTitle, action: action)
                }
            }
            .frame(minWidth: MAYNControlMetrics.trailingLaneMinWidth, alignment: .trailing)
        }
        .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
        .padding(.vertical, MAYNControlMetrics.rowVerticalPadding)
        .frame(minHeight: 78)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovering ? MAYNTheme.hover : Color.clear)
        .contentShape(Rectangle())
        .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isHovering)
        .onHover { isHovering = presentation.actionTitle != nil && $0 }
        .accessibilityValue(hasUsableAPIKey ? "" : "API key required")
    }

    private var presentation: VoiceASRModelRowPresentation {
        VoiceASRModelRowPresentation.cloudModel(
            isSelected: isSelected,
            hasUsableAPIKey: hasUsableAPIKey
        )
    }
}

struct VoiceCloudASRSetupDrawer: View {
    @Binding var isExpanded: Bool
    let providerKind: VoiceASRProviderKind
    @Binding var apiKey: String
    let isTesting: Bool
    let statusMessage: String?
    let testConnection: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            header

            if isExpanded {
                drawerContent
            }
        }
        .animation(MAYNMotion.panelAnimation(reduceMotion: reduceMotion), value: isExpanded)
    }

    private var header: some View {
        Button {
            withAnimation(MAYNMotion.panelAnimation(reduceMotion: reduceMotion)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(alignment: .center, spacing: MAYNControlMetrics.rowControlSpacing) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(VoiceCloudASRSetupDrawerPresentation.title(for: providerKind))
                        .font(.callout)
                    Text(VoiceCloudASRSetupDrawerPresentation.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    StatusPill(text: setupStatus.text, kind: setupStatus.kind.statusPillKind)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .frame(width: 14, height: 14)
                }
                .frame(minWidth: MAYNControlMetrics.trailingLaneMinWidth, alignment: .trailing)
            }
            .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
            .padding(.vertical, MAYNControlMetrics.rowVerticalPadding)
            .frame(minHeight: MAYNControlMetrics.rowMinHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? MAYNTheme.hover : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(VoiceCloudASRSetupDrawerPresentation.title(for: providerKind))
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }

    private var drawerContent: some View {
        VStack(spacing: 0) {
            MAYNDivider()
            MAYNSettingsRow(title: providerKind.apiKeyLabel) {
                MAYNSecureField(
                    placeholder: providerKind.apiKeyPlaceholder,
                    text: $apiKey,
                    width: MAYNControlMetrics.wideTextFieldWidth
                )
            }
            if let actionTitle = VoiceASRProviderControlsPresentation.connectionActionTitle(for: providerKind) {
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Connection",
                    subtitle: "Test after adding or changing the API key."
                ) {
                    VStack(alignment: .trailing, spacing: 6) {
                        MAYNButton(isTesting ? "Testing..." : actionTitle) {
                            testConnection()
                        }
                        .disabled(isTesting)

                        if let statusMessage {
                            Text(statusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
        }
    }

    private var setupStatus: VoiceCloudASRSetupStatusPresentation {
        VoiceCloudASRSetupDrawerPresentation.status(
            apiKey: apiKey,
            isTesting: isTesting,
            statusMessage: statusMessage
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
