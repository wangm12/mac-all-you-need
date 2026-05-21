import AppKit
import AVFoundation
import Core
import FluidAudio
import Platform
import SwiftUI
import UniformTypeIdentifiers

struct VoiceDestinationView: View {
    let controller: AppController
    @AppStorage(VoiceFunctionTab.storageKey, store: AppGroupSettings.defaults) private var selectedTabRaw = VoiceFunctionTab.dictate.rawValue
    @AppStorage(VoiceAudioSettings.microphoneIDKey, store: AppGroupSettings.defaults) private var preferredMicrophoneID = VoiceAudioSettings.systemMicrophoneID
    @AppStorage("voice.audio.interactionSounds", store: AppGroupSettings.defaults) private var interactionSounds = true
    @AppStorage("voice.audio.muteWhenDictating", store: AppGroupSettings.defaults) private var muteWhenDictating = false
    @AppStorage("voice.asr.groq.apiSetupExpanded", store: AppGroupSettings.defaults) private var isCloudAPISetupExpanded = false
    @State private var shortcut: Platform.HotkeyDescriptor
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
    @State private var transcripts: [VoiceTranscript] = []
    @State private var transcriptPage = 0
    @State private var selectedTranscriptIDs: Set<String> = []
    @State private var voiceHistorySettings = VoiceHistorySettings()
    @State private var historyToast: VoiceHistoryUndoToken?
    @State private var toastClearTask: Task<Void, Never>?
    @State private var transcriptAnchorID: String?
    @State private var microphoneOptions = VoiceMicrophoneOptionDescriptor.available()
    @State private var modelDownloadStatus: [VoiceASRModelID: String] = [:]
    @State private var modelDownloadFractions: [VoiceASRModelID: Double] = [:]
    @State private var downloadingModelID: VoiceASRModelID?
    private let microphoneRefreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init(controller: AppController) {
        self.controller = controller
        let activationSettings = VoiceActivationSettingsStore.load()
        let asrSettings = VoiceASRSettingsStore.load()
        let cloudSettings = VoiceCloudASRSettingsStore.load()
        let cleanupSettings = controller.voiceCleanupSettings()
        let recognitionLanguageHint = asrSettings.providerKind.isCloud
            ? cloudSettings.languageHint
            : asrSettings.languageHint
        _shortcut = State(initialValue: activationSettings.shortcut)
        _mode = State(initialValue: activationSettings.mode)
        _selectedASRModelID = State(initialValue: asrSettings.modelID)
        _languageHint = State(initialValue: recognitionLanguageHint)
        _asrProviderKind = State(initialValue: asrSettings.providerKind)
        _cloudModelID = State(
            initialValue: asrSettings.providerKind.isCloud
                ? cloudSettings.modelID(for: asrSettings.providerKind)
                : cloudSettings.modelID
        )
        _cloudLanguageHint = State(initialValue: recognitionLanguageHint)
        let cloudKeys = Dictionary(
            uniqueKeysWithValues: VoiceASRProviderKind.allCases
                .filter(\.isCloud)
                .map { ($0, controller.cloudASRAPIKey(for: $0)) }
        )
        _cloudAPIKeys = State(initialValue: cloudKeys)
        _cloudSetupProviderKind = State(initialValue: asrSettings.providerKind.isCloud ? asrSettings.providerKind : cloudSettings.modelID.providerKind)
        _cleanupEnabled = State(initialValue: cleanupSettings.isEnabled)
        _cleanupProvider = State(initialValue: cleanupSettings.provider)
        _cleanupModel = State(initialValue: cleanupSettings.model)
        _cleanupBaseURLString = State(initialValue: cleanupSettings.baseURLString)
        _cleanupAPIKey = State(initialValue: controller.voiceCleanupAPIKey(for: cleanupSettings.provider))
        _cleanupTimeoutSeconds = State(initialValue: cleanupSettings.timeoutSeconds)
        _cleanupLatencyPolicy = State(initialValue: cleanupSettings.latencyPolicy)
        _onboardingProgress = State(initialValue: VoiceOnboardingProgressStore.load())
    }

    private var selectedTab: Binding<VoiceFunctionTab> {
        Binding {
            VoiceFunctionTab.storedSelection(selectedTabRaw)
        } set: { tab in
            selectedTabRaw = tab.rawValue
        }
    }

    var body: some View {
        FunctionPageShell(
            title: "Voice",
            subtitle: "Dictation, transcript history, dictionary, app profiles, and voice settings.",
            selection: selectedTab,
            toolbar: {
                if VoiceMainPagePresentation.showsHeaderShortcut {
                    MainHeaderShortcutDisplay(
                        text: MainToolHeaderShortcutModel.display(
                            for: .voice,
                            hotkeys: HotkeyMapStore.load(),
                            voiceSettings: VoiceActivationSettings(shortcut: shortcut, mode: mode)
                        )
                    )
                }
            }
        ) {
            switch VoiceFunctionTab.storedSelection(selectedTabRaw) {
            case .dictate:
                FunctionPageScrollContent {
                    voiceDictateSection
                    voiceSetupSection
                }
            case .models:
                FunctionPageScrollContent {
                    voiceRecognitionModelsSection
                    voiceCleanupSection
                }
            case .history:
                FunctionPageScrollContent {
                    voiceHistorySection
                }
            case .dictionary:
                VoiceDictionaryPage(controller: controller, showsHeader: false)
            case .personalization:
                FunctionPageScrollContent {
                    VoicePersonalizationPage(controller: controller)
                }
            case .settings:
                FunctionPageScrollContent {
                    voiceActivationSection
                    voiceModelSummarySection
                    voiceAudioSection
                }
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)) { _ in
            refreshMicrophoneOptions()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)) { _ in
            refreshMicrophoneOptions()
        }
        .onReceive(microphoneRefreshTimer) { _ in
            refreshMicrophoneOptions()
        }
        .onChange(of: cleanupProvider) { _, provider in
            cleanupModel = provider.defaultModel
            cleanupBaseURLString = provider.defaultBaseURLString
            cleanupAPIKey = controller.voiceCleanupAPIKey(for: provider)
        }
        .onChange(of: languageHint) { _, hint in
            cloudLanguageHint = hint
            controller.applyVoiceASRSettings(currentAppliedASRSettings.updating(languageHint: hint))
            controller.applyCloudASRSettings(VoiceCloudASRSettings(modelID: cloudModelID, languageHint: hint))
        }
        .onChange(of: asrProviderKind) { _, providerKind in
            applyASRProviderSelection(providerKind)
        }
        .onChange(of: cloudModelID) { _, newModelID in
            cloudSetupProviderKind = newModelID.providerKind
            applyCloudDropdownSettings()
        }
    }

    private var voiceDictateSection: some View {
        MAYNSection(title: "Dictate") {
            MAYNSettingsRow(
                title: "State",
                subtitle: voiceStateTitle
            ) {
                StatusPill(text: voiceStatusText, kind: voiceStatusKind)
            }
        }
    }

    private var voiceSetupSection: some View {
        MAYNSection(title: "Setup") {
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
                        reload()
                    }
                    MAYNButton("Restart") {
                        controller.restartVoiceOnboarding()
                        reload()
                    }
                }
            }
        }
    }

    private var voiceRecognitionModelsSection: some View {
        MAYNSection(
            title: "Recognition model",
            subtitle: "Choose the local or BYOK cloud recognizer used for dictation."
        ) {
            MAYNSettingsRow(
                title: "Dictation language",
                subtitle: "Auto-detect is best for mixed Chinese and English; switch to one language only when results drift."
            ) {
                MAYNDropdown(
                    selection: $languageHint,
                    options: Array(VoiceASRLanguageHint.allCases),
                    title: VoiceLanguageModePresentation.title,
                    width: MAYNControlMetrics.widePickerWidth
                )
            }
            MAYNDivider()
            VoiceCloudASRSetupDrawer(
                isExpanded: $isCloudAPISetupExpanded,
                providerKind: cloudSetupProviderKind,
                apiKey: cloudAPIKeyBinding,
                isTesting: isTestingCloud,
                statusMessage: cloudStatusMessage,
                testConnection: testCloudConnection
            )
            MAYNDivider()
            ForEach(Array(VoiceModelCatalog.cloudASRModels.enumerated()), id: \.element.id) { index, descriptor in
                let modelID = descriptor.cloudASRModelID!
                if index > 0 { MAYNDivider() }
                VoiceCloudASRModelRow(
                    modelID: modelID,
                    isSelected: VoiceASRModelSelectionState.isCloudModelSelected(
                        providerKind: asrProviderKind,
                        selectedModelID: cloudModelID,
                        modelID: modelID,
                        hasUsableAPIKey: hasUsableCloudAPIKey(for: modelID.providerKind)
                    ),
                    hasUsableAPIKey: hasUsableCloudAPIKey(for: modelID.providerKind),
                    action: { selectCloudModel(modelID) }
                )
            }
            MAYNDivider()
            ForEach(Array(VoiceModelCatalog.localASRModels.enumerated()), id: \.element.id) { index, descriptor in
                if index > 0 { MAYNDivider() }
                if let modelID = descriptor.localASRModelID {
                    VoiceASRModelRow(
                        modelID: modelID,
                        isSelected: VoiceASRModelSelectionState.isLocalModelSelected(
                            providerKind: asrProviderKind,
                            selectedModelID: selectedASRModelID,
                            modelID: modelID
                        ),
                        isDownloaded: isDownloaded(modelID),
                        statusMessage: modelDownloadStatus[modelID],
                        downloadFraction: modelDownloadFractions[modelID],
                        isDownloading: downloadingModelID == modelID,
                        onSelect: { selectModel(modelID) },
                        onShowInFinder: { showModelInFinder(modelID) },
                        onDelete: { deleteModel(modelID) }
                    )
                } else {
                    VoiceUnsupportedASRModelRow(descriptor: descriptor)
                }
            }
        }
    }

    private var voiceHistorySection: some View {
        let page = voiceTranscriptPageState
        return VStack(spacing: 12) {
            MAYNSection(title: "Recent transcripts") {
                if transcripts.isEmpty {
                    MAYNSettingsRow(
                        title: "No transcripts yet",
                        subtitle: "Completed voice dictations appear here after transcription and paste."
                    ) {
                        EmptyView()
                    }
                } else {
                    ForEach(Array(page.visible.enumerated()), id: \.element.id) { index, transcript in
                        if index > 0 { MAYNDivider() }
                        VoiceTranscriptHistoryRow(
                            transcript: transcript,
                            isSelected: selectedTranscriptIDs.contains(transcript.id),
                            onSelect: { selectVoiceTranscript(transcript) },
                            onCopy: { copyVoiceTranscripts(ids: [transcript.id]) },
                            onRetry: { retryTranscript(transcript) },
                            onDownload: { downloadTranscript(transcript) },
                            onDelete: { deleteTranscriptWithUndo(transcript) }
                        )
                    }

                    if page.totalPages > 1 {
                        MAYNDivider()
                        VoiceTranscriptPaginationFooter(
                            rangeText: page.rangeText,
                            currentPage: page.currentPage,
                            totalPages: page.totalPages,
                            canGoPrevious: page.canGoPrevious,
                            canGoNext: page.canGoNext,
                            previous: { transcriptPage = max(0, transcriptPage - 1) },
                            next: { transcriptPage = min(page.totalPages - 1, transcriptPage + 1) }
                        )
                    }
                }
            }

            VoiceHistoryStorageHeader(settings: $voiceHistorySettings)
                .onChange(of: voiceHistorySettings) { _, new in
                    controller.saveVoiceHistorySettings(new)
                }
        }
        .overlay(alignment: .bottom) {
            if let toast = historyToast {
                VoiceHistoryToastView(message: toast.message) {
                    toast.undo()
                    toastClearTask?.cancel()
                    historyToast = nil
                    reload()
                }
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress { keyPress in
            handleVoiceHistoryKeyPress(keyPress)
        }
    }

    private struct VoiceTranscriptPageState {
        let visible: [VoiceTranscript]
        let currentPage: Int
        let totalPages: Int
        let totalItems: Int
        let pageSize: Int
        var canGoPrevious: Bool { currentPage > 0 }
        var canGoNext: Bool { currentPage < totalPages - 1 }
        var rangeText: String {
            guard totalItems > 0 else { return "0 of 0" }
            let start = currentPage * pageSize + 1
            let end = min(start + visible.count - 1, totalItems)
            return "\(start)–\(end) of \(totalItems)"
        }
    }

    private var voiceTranscriptPageState: VoiceTranscriptPageState {
        let size = 15
        let total = transcripts.count
        let pages = max(1, Int(ceil(Double(total) / Double(size))))
        let page = min(max(0, transcriptPage), pages - 1)
        let start = page * size
        let end = min(start + size, total)
        let visible = start < end ? Array(transcripts[start ..< end]) : []
        return VoiceTranscriptPageState(
            visible: visible, currentPage: page, totalPages: pages, totalItems: total, pageSize: size
        )
    }

    private var voiceActivationSection: some View {
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
    }

    private var voiceModelSummarySection: some View {
        MAYNSection(title: "Models") {
            MAYNSettingsRow(
                title: "Recognition model",
                subtitle: recognitionModelSummary
            ) {
                MAYNButton("Open Models") {
                    selectedTabRaw = VoiceFunctionTab.models.rawValue
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
    }

    private var voiceAudioSection: some View {
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
    }

    private var voiceCleanupSection: some View {
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
            if cleanupProvider == .ollama {
                MAYNDivider()
                VoiceOllamaCleanupControls(
                    controller: controller,
                    model: $cleanupModel,
                    baseURLString: $cleanupBaseURLString,
                    statusMessage: $cleanupStatusMessage
                )
            }
            if cleanupProvider.requiresAPIKey {
                MAYNDivider()
                MAYNSettingsRow(title: "API key") {
                    MAYNSecureField(text: $cleanupAPIKey)
                }
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
            MAYNSettingsRow(
                title: "Latency policy",
                subtitle: cleanupLatencyPolicy.subtitle
            ) {
                MAYNDropdown(
                    selection: $cleanupLatencyPolicy,
                    options: Array(VoiceCleanupLatencyPolicy.allCases),
                    title: { $0.label },
                    width: MAYNControlMetrics.widePickerWidth
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
    }

    private func reload() {
        onboardingProgress = VoiceOnboardingProgressStore.load()
        let asrSettings = VoiceASRSettingsStore.load()
        let cloudSettings = VoiceCloudASRSettingsStore.load()
        let recognitionLanguageHint = asrSettings.providerKind.isCloud
            ? cloudSettings.languageHint
            : asrSettings.languageHint
        selectedASRModelID = asrSettings.modelID
        languageHint = recognitionLanguageHint
        asrProviderKind = asrSettings.providerKind
        cloudModelID = asrSettings.providerKind.isCloud
            ? cloudSettings.modelID(for: asrSettings.providerKind)
            : cloudSettings.modelID
        cloudLanguageHint = recognitionLanguageHint
        cloudAPIKeys = Dictionary(
            uniqueKeysWithValues: VoiceASRProviderKind.allCases
                .filter(\.isCloud)
                .map { ($0, controller.cloudASRAPIKey(for: $0)) }
        )
        cloudSetupProviderKind = asrSettings.providerKind.isCloud ? asrSettings.providerKind : cloudSettings.modelID.providerKind
        transcripts = controller.listRecentVoiceTranscripts(limit: 500)
        transcriptPage = 0
        pruneVoiceTranscriptSelection()
        refreshMicrophoneOptions()
        voiceHistorySettings = controller.loadVoiceHistorySettings()
    }

    private var voiceTranscriptIDs: [String] {
        transcripts.map(\.id)
    }

    private func selectVoiceTranscript(_ transcript: VoiceTranscript) {
        let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let state = MainVoiceTranscriptHistoryPresentation.selection(
            afterClicking: transcript.id,
            orderedIDs: voiceTranscriptIDs,
            selectedIDs: selectedTranscriptIDs,
            anchorID: transcriptAnchorID,
            command: modifiers.contains(.command),
            shift: modifiers.contains(.shift)
        )
        selectedTranscriptIDs = state.selectedIDs
        transcriptAnchorID = state.anchorID
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

    private func handleVoiceHistoryKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        let raw = keyPress.key.character

        if keyPress.modifiers.contains(.command), String(raw).lowercased() == "a" {
            selectedTranscriptIDs = Set(voiceTranscriptIDs)
            transcriptAnchorID = voiceTranscriptIDs.first
            return .handled
        }

        if keyPress.modifiers.contains(.command), String(raw).lowercased() == "c" {
            copyVoiceTranscripts(ids: effectiveVoiceTranscriptIDs())
            return .handled
        }

        if keyPress.modifiers.contains(.command), Self.isDeleteKey(raw) {
            deleteVoiceTranscripts(ids: effectiveVoiceTranscriptIDs())
            return .handled
        }

        switch raw {
        case " ":
            previewVoiceTranscript(id: effectiveVoiceTranscriptIDs().first)
            return .handled
        case "\r":
            copyVoiceTranscripts(ids: effectiveVoiceTranscriptIDs())
            return .handled
        case Character(UnicodeScalar(NSDownArrowFunctionKey)!):
            moveVoiceTranscriptSelection(delta: 1)
            return .handled
        case Character(UnicodeScalar(NSUpArrowFunctionKey)!):
            moveVoiceTranscriptSelection(delta: -1)
            return .handled
        default:
            return .ignored
        }
    }

    private func moveVoiceTranscriptSelection(delta: Int) {
        let previousIndex = transcriptAnchorID.flatMap { voiceTranscriptIDs.firstIndex(of: $0) } ?? 0
        let state = MainVoiceTranscriptHistoryPresentation.selection(
            afterMovingFrom: transcriptAnchorID,
            orderedIDs: voiceTranscriptIDs,
            delta: delta
        )
        selectedTranscriptIDs = state.selectedIDs
        transcriptAnchorID = state.anchorID

        if PreviewPanel.isVisible,
           let transcriptAnchorID {
            let nextIndex = voiceTranscriptIDs.firstIndex(of: transcriptAnchorID) ?? previousIndex
            previewVoiceTranscript(
                id: transcriptAnchorID,
                direction: PreviewPanelTransitionDirection.horizontal(from: previousIndex, to: nextIndex)
            )
        }
    }

    private func effectiveVoiceTranscriptIDs() -> [String] {
        MainVoiceTranscriptHistoryPresentation.effectiveIDs(
            selectedIDs: selectedTranscriptIDs,
            anchorID: transcriptAnchorID,
            orderedIDs: voiceTranscriptIDs
        )
    }

    private func copyVoiceTranscripts(ids: [String]) {
        let strings = ids.compactMap { id in
            transcripts.first { $0.id == id }.map(MainVoiceTranscriptHistoryPresentation.displayText)
        }.filter { $0 != "Empty transcript" }
        guard !strings.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(strings.joined(separator: "\n"), forType: .string)
        NSPasteboard.general.setData(Data([0]), forType: PasteboardUTI.daemonWrite)
        CopyHUD.show(strings.count == 1 ? "Copied" : "Copied \(strings.count)")
    }

    private func previewVoiceTranscript(
        id: String?,
        direction: PreviewPanelTransitionDirection = .none
    ) {
        guard let id,
              let transcript = transcripts.first(where: { $0.id == id })
        else { return }

        PreviewPanel.show(
            .text(MainVoiceTranscriptHistoryPresentation.displayText(transcript), monospaced: false),
            metadata: PreviewPanelMetadata(
                title: "Voice transcript",
                subtitle: "\(CompactTimestamp.format(transcript.endedAt)) · \(transcript.language.rawValue)",
                badge: "\(transcript.durationMs) ms",
                symbol: "waveform"
            ),
            direction: direction
        )
    }

    private func deleteVoiceTranscripts(ids: [String]) {
        guard !ids.isEmpty else { return }
        do {
            try controller.deleteVoiceTranscripts(ids: ids)
            selectedTranscriptIDs.subtract(ids)
            if let transcriptAnchorID, ids.contains(transcriptAnchorID) {
                self.transcriptAnchorID = nil
            }
            reload()
            CopyHUD.show(ids.count == 1 ? "Deleted" : "Deleted \(ids.count)", symbol: "trash.fill")
            if PreviewPanel.isVisible {
                PreviewPanel.dismiss()
            }
        } catch {
            CopyHUD.show("Delete failed", symbol: "exclamationmark.triangle.fill")
        }
    }

    private func pruneVoiceTranscriptSelection() {
        let existingIDs = Set(voiceTranscriptIDs)
        selectedTranscriptIDs.formIntersection(existingIDs)
        if let transcriptAnchorID, !existingIDs.contains(transcriptAnchorID) {
            self.transcriptAnchorID = selectedTranscriptIDs.first ?? voiceTranscriptIDs.first
        }
    }

    private func retryTranscript(_ transcript: VoiceTranscript) {
        Task { @MainActor in
            do {
                _ = try await controller.retryVoiceTranscript(id: transcript.id)
                reload()
            } catch {
                CopyHUD.show("Retry failed", symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    private func downloadTranscript(_ transcript: VoiceTranscript) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        panel.nameFieldStringValue = "voice-\(formatter.string(from: transcript.endedAt)).wav"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try controller.downloadVoiceAudio(transcript: transcript, to: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't save audio"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func deleteTranscriptWithUndo(_ transcript: VoiceTranscript) {
        let token = controller.deleteVoiceTranscriptWithUndo(transcript)
        toastClearTask?.cancel()
        historyToast = token
        let task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            historyToast = nil
        }
        toastClearTask = task
        reload()
    }

    private static func isDeleteKey(_ character: Character) -> Bool {
        character == Character(UnicodeScalar(NSDeleteCharacter)!)
            || character == Character(UnicodeScalar(NSBackspaceCharacter)!)
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

    private var activationShortcutBinding: Binding<Platform.HotkeyDescriptor> {
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

    private func applyActivationShortcut(_ descriptor: Platform.HotkeyDescriptor) {
        shortcut = descriptor
        applyActivationSettingsIfValid()
    }

    private func toggleVoice() {
        if controller.voiceCoordinator.state == .recording {
            Task {
                await controller.voiceCoordinator.stopRecordingAndPaste()
                await MainActor.run { reload() }
            }
        } else {
            Task { await controller.voiceCoordinator.startRecording() }
        }
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
                            modelDownloadStatus[modelID] = VoiceModelDownloadPresenter.describe(progress)
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

    private func shortcutCandidateIssue(_ descriptor: Platform.HotkeyDescriptor) -> HotkeyValidationIssue? {
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

    private var voiceStatusText: String {
        switch controller.voiceCoordinator.state {
        case .idle: "Ready"
        case .recording: "Listening"
        case .transcribing: "Transcribing"
        case .pasting: "Pasting"
        case .error: "Error"
        }
    }

    private var voiceStatusKind: StatusPill.Kind {
        switch controller.voiceCoordinator.state {
        case .idle: .success
        case .recording, .transcribing, .pasting: .progress
        case .error: .warning
        }
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
}

private struct VoiceTranscriptPaginationFooter: View {
    let rangeText: String
    let currentPage: Int
    let totalPages: Int
    let canGoPrevious: Bool
    let canGoNext: Bool
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(rangeText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            MAYNButton("Previous", action: previous)
                .disabled(!canGoPrevious)

            Text("Page \(currentPage + 1) of \(totalPages)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 86)

            MAYNButton("Next", action: next)
                .disabled(!canGoNext)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct VoiceTranscriptHistoryRow: View {
    let transcript: VoiceTranscript
    let isSelected: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onRetry: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(displayText)
                    .font(.callout)
                    .lineLimit(2)
                Text(metadataLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                    onCopy()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy transcript")
                .opacity(isHovering || isSelected ? 1 : 0)
                .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isHovering)
                .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isSelected)

            VoiceTranscriptRowMenu(
                hasAudio: transcript.audioPath != nil,
                onRetry: onRetry,
                onDownload: onDownload,
                onDelete: onDelete
            )
            .opacity(isHovering || isSelected ? 1 : 0)
            .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isHovering)
            .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isSelected)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 62)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .simultaneousGesture(TapGesture(count: 2).onEnded { onCopy() })
        .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isHovering)
        .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isSelected)
        .onHover { isHovering = $0 }
    }

    private var displayText: String {
        MainVoiceTranscriptHistoryPresentation.displayText(transcript)
    }

    private var metadataLine: String {
        let time = CompactTimestamp.format(transcript.endedAt)
        let duration = formatDuration(ms: transcript.durationMs)
        return "\(time) · \(transcript.language.rawValue) · \(transcript.modelIdentifier) · \(duration)"
    }

    private func formatDuration(ms: Int) -> String {
        let seconds = Double(ms) / 1000.0
        if seconds < 60 { return String(format: "%.1f s", seconds) }
        let minutes = Int(seconds / 60)
        let remainder = Int(seconds.truncatingRemainder(dividingBy: 60))
        return "\(minutes)m \(remainder)s"
    }

    private var rowBackground: Color {
        if isSelected { return Color.primary.opacity(0.10) }
        if isHovering { return MAYNTheme.hover }
        return .clear
    }
}

private enum VoiceModelDownloadPresenter {
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

private struct VoiceASRModelRow: View {
    let modelID: VoiceASRModelID
    let isSelected: Bool
    let isDownloaded: Bool
    let statusMessage: String?
    let downloadFraction: Double?
    let isDownloading: Bool
    let onSelect: () -> Void
    let onShowInFinder: () -> Void
    let onDelete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                        MAYNButton(actionTitle) {
                            onSelect()
                        }
                    }
                    if isDownloaded, !isDownloading {
                        HStack(spacing: 6) {
                            MAYNButton("Show", height: 24, action: onShowInFinder)
                            MAYNButton("Delete", role: .destructive, height: 24, action: onDelete)
                        }
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

            VoiceModelDetailLines(
                strengths: modelID.strengths,
                tradeoffs: modelID.tradeoffs
            )
        }
        .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
        .padding(.vertical, 14)
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

private struct VoiceModelDetailLines: View {
    let strengths: String
    let tradeoffs: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(strengths, systemImage: "checkmark.circle")
            Label(tradeoffs, systemImage: "exclamationmark.circle")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
