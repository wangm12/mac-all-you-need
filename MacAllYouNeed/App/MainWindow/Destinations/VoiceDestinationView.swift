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
    @State private var isShowingCleanupPicker = false
    @State private var cleanupPickerSelectedProvider: VoiceCleanupProviderKind = .anthropic
    @State private var cleanupPickerFilter: VoiceCleanupPickerFilter = .all
    @State private var cleanupPickerSearchText = ""
    @State private var cleanupPickerDraftModel = ""
    @State private var cleanupPickerDraftBaseURL = ""
    @State private var cleanupPickerDraftAPIKey = ""
    @State private var cleanupPickerDraftTimeout = 7
    @State private var cleanupPickerDraftLatency: VoiceCleanupLatencyPolicy = .balanced2s
    @State private var cleanupPickerPreloadedAPIKeys: [VoiceCleanupProviderKind: String] = [:]
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
    @State private var isShowingEnginePicker = false
    @State private var pickerSelectedEngineID: VoiceEngineID
    @State private var pickerFilter: VoiceEnginePickerFilter = .all
    @State private var pickerSearchText = ""
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
        _pickerSelectedEngineID = State(
            initialValue: VoiceEngineCatalogPresentation.currentEngineID(
                providerKind: asrSettings.providerKind,
                selectedLocalModelID: asrSettings.modelID,
                selectedCloudModelID: asrSettings.providerKind.isCloud
                    ? cloudSettings.modelID(for: asrSettings.providerKind)
                    : cloudSettings.modelID
            )
        )
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
        .onChange(of: cleanupEnabled) { _, _ in
            applyCleanupSettings()
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
        .sheet(isPresented: $isShowingEnginePicker) {
            voiceEnginePickerSheet
        }
        .sheet(isPresented: $isShowingCleanupPicker) {
            voiceCleanupPickerSheet
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
            title: "Recognition",
            subtitle: "Pick your recognition engine and language; tap the engine row to open the full picker."
        ) {
            MAYNSettingsRow(
                title: "Recognition engine",
                subtitle: recognitionEngineRowSubtitle,
                belowSubtitle: {
                    AnyView(StatusPill(text: recognitionEngineSingleTag, kind: .neutral))
                }
            ) {
                MAYNButton("Change...") {
                    openVoiceEnginePicker()
                }
            }
            MAYNDivider()
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
                        VoiceTranscriptHistoryRowView(
                            transcript: transcript,
                            surface: .main,
                            isSelected: selectedTranscriptIDs.contains(transcript.id),
                            onSelect: { selectVoiceTranscript(transcript) },
                            onCopy: { copyVoiceTranscripts(ids: [transcript.id]) },
                            onRetry: { retryTranscript(transcript) },
                            onDownload: { downloadTranscript(transcript) },
                            onDelete: { deleteTranscriptWithUndo(transcript) }
                        )
                    }

                    if page.pagination.totalPages > 1 {
                        MAYNDivider()
                        MAYNListPaginationFooter(
                            state: page.pagination,
                            visibleItemCount: page.visible.count,
                            goToPage: { transcriptPage = $0 }
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
        let pagination: MAYNListPaginationState
    }

    private static let voiceTranscriptPageSize = 15

    private var voiceTranscriptPageState: VoiceTranscriptPageState {
        let pagination = MAYNListPagination.make(
            totalItems: transcripts.count,
            requestedPage: transcriptPage,
            pageSize: Self.voiceTranscriptPageSize
        )
        let visible = MAYNListPagination.slice(transcripts, pagination: pagination)
        return VoiceTranscriptPageState(visible: visible, pagination: pagination)
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
        MAYNSection(title: "Recognition") {
            MAYNSettingsRow(
                title: "Recognition engine",
                subtitle: recognitionEngineRowSubtitle,
                belowSubtitle: {
                    AnyView(StatusPill(text: recognitionEngineSingleTag, kind: .neutral))
                }
            ) {
                MAYNButton("Choose recognition engine") {
                    selectedTabRaw = VoiceFunctionTab.models.rawValue
                }
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Cleanup model",
                subtitle: cleanupRowSubtitle,
                belowSubtitle: {
                    AnyView(StatusPill(text: cleanupSavedSelectionLine, kind: .neutral))
                }
            ) {
                MAYNButton("Change...") {
                    openCleanupPicker()
                }
            }
            .accessibilityLabel("Cleanup model")
            .accessibilityValue(cleanupAccessibilitySummary)
        }
    }

    private var voiceEnginePickerSheet: some View {
        VoiceEnginePickerSheet(
            selectedEngineID: $pickerSelectedEngineID,
            filter: $pickerFilter,
            searchText: $pickerSearchText,
            currentEngineID: currentEngineID,
            entries: voiceEnginePickerEntries,
            onClose: { isShowingEnginePicker = false }
        ) { engineID in
            voiceEngineDetailPane(for: engineID)
        }
    }

    private var voiceEnginePickerEntries: [VoiceEngineListEntry] {
        VoiceEngineCatalogPresentation.pickerEntries()
    }

    private var currentEngineID: VoiceEngineID {
        VoiceEngineCatalogPresentation.currentEngineID(
            providerKind: asrProviderKind,
            selectedLocalModelID: selectedASRModelID,
            selectedCloudModelID: cloudModelID
        )
    }

    private func openVoiceEnginePicker() {
        pickerSelectedEngineID = currentEngineID
        pickerFilter = .all
        pickerSearchText = ""
        isShowingEnginePicker = true
    }

    private var voiceCleanupPickerSheet: some View {
        VoiceCleanupPickerSheet(
            selectedProvider: $cleanupPickerSelectedProvider,
            filter: $cleanupPickerFilter,
            searchText: $cleanupPickerSearchText,
            currentProvider: cleanupProvider,
            showsAppliedProviderCheckmark: cleanupEnabled,
            controller: controller,
            draftModel: $cleanupPickerDraftModel,
            draftBaseURL: $cleanupPickerDraftBaseURL,
            draftAPIKey: $cleanupPickerDraftAPIKey,
            draftTimeout: $cleanupPickerDraftTimeout,
            draftLatency: $cleanupPickerDraftLatency,
            cleanupEnabled: cleanupEnabled,
            statusMessage: $cleanupStatusMessage,
            onClose: { isShowingCleanupPicker = false },
            onSelect: { useCleanupModelFromPicker() }
        ) { provider in
            VoiceCleanupPickerDetailView(
                controller: controller,
                savedProvider: cleanupProvider,
                selectedProvider: provider,
                draftModel: $cleanupPickerDraftModel,
                draftBaseURL: $cleanupPickerDraftBaseURL,
                draftAPIKey: $cleanupPickerDraftAPIKey,
                draftTimeout: $cleanupPickerDraftTimeout,
                draftLatency: $cleanupPickerDraftLatency,
                cleanupEnabled: cleanupEnabled,
                statusMessage: $cleanupStatusMessage
            )
        }
        .onChange(of: cleanupPickerSelectedProvider) { _, newValue in
            syncCleanupPickerDraftForSelection(newValue)
        }
        .onChange(of: cleanupPickerDraftAPIKey) { _, newValue in
            cleanupPickerPreloadedAPIKeys[cleanupPickerSelectedProvider] = newValue
        }
    }

    private func openCleanupPicker() {
        cleanupPickerPreloadedAPIKeys = Dictionary(
            uniqueKeysWithValues: VoiceCleanupProviderKind.allCases
                .filter(\.requiresAPIKey)
                .map { ($0, controller.voiceCleanupAPIKey(for: $0)) }
        )
        cleanupPickerSelectedProvider = cleanupProvider
        cleanupPickerDraftModel = cleanupModel
        cleanupPickerDraftBaseURL = cleanupBaseURLString
        cleanupPickerDraftAPIKey = cleanupAPIKey
        cleanupPickerDraftTimeout = cleanupTimeoutSeconds
        cleanupPickerDraftLatency = cleanupLatencyPolicy
        cleanupPickerFilter = .all
        cleanupPickerSearchText = ""
        isShowingCleanupPicker = true
    }

    /// When the user selects a list row, load defaults for other providers or the saved values when the row matches the applied provider.
    private func syncCleanupPickerDraftForSelection(_ provider: VoiceCleanupProviderKind) {
        if provider == cleanupProvider {
            cleanupPickerDraftModel = cleanupModel
            cleanupPickerDraftBaseURL = cleanupBaseURLString
            cleanupPickerDraftAPIKey = cleanupAPIKey
            cleanupPickerDraftTimeout = cleanupTimeoutSeconds
            cleanupPickerDraftLatency = cleanupLatencyPolicy
        } else {
            cleanupPickerDraftModel = provider.defaultModel
            cleanupPickerDraftBaseURL = provider.defaultBaseURLString
            cleanupPickerDraftAPIKey = cleanupPickerPreloadedAPIKeys[provider]
                ?? controller.voiceCleanupAPIKey(for: provider)
        }
    }

    private func useCleanupModelFromPicker() {
        cleanupProvider = cleanupPickerSelectedProvider
        cleanupModel = cleanupPickerDraftModel
        cleanupBaseURLString = cleanupPickerDraftBaseURL
        cleanupAPIKey = cleanupPickerDraftAPIKey
        cleanupTimeoutSeconds = cleanupPickerDraftTimeout
        cleanupLatencyPolicy = cleanupPickerDraftLatency
        applyCleanupSettings()
        isShowingCleanupPicker = false
    }

    @ViewBuilder
    private func voiceEngineDetailPane(for engineID: VoiceEngineID) -> some View {
        switch engineID {
        case let .local(modelID):
            voiceLocalEngineDetailPane(for: modelID)
        case let .cloud(modelID):
            voiceCloudEngineDetailPane(for: modelID)
        case let .experimental(descriptorID):
            voiceExperimentalEngineDetailPane(for: descriptorID)
        }
    }

    private func voiceLocalEngineDetailPane(for modelID: VoiceASRModelID) -> some View {
        let isCurrent = currentEngineID == .local(modelID)
        let installed = isDownloaded(modelID)
        let isDownloading = downloadingModelID == modelID
        let downloadFraction = modelDownloadFractions[modelID]
        let statusText: String
        let statusKind: StatusPill.Kind

        if isDownloading {
            statusText = "Downloading"
            statusKind = .progress
        } else if isCurrent {
            statusText = "In use"
            statusKind = .success
        } else if installed {
            statusText = "Installed"
            statusKind = .neutral
        } else {
            statusText = "Not installed"
            statusKind = .warning
        }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Local engine")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                StatusPill(text: statusText, kind: statusKind)
            }

            Text(modelID.title)
                .font(.title3.weight(.semibold))
            Text(modelID.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                StatusPill(text: modelID.diskLabel, kind: .neutral)
                StatusPill(text: modelID.requiresOSLabel, kind: .neutral)
                StatusPill(text: VoiceLanguageModePresentation.title(for: languageHint), kind: .neutral)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Details")
                    .font(.callout.weight(.semibold))
                Label(modelID.strengths, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(modelID.tradeoffs, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let downloadFraction, isDownloading {
                ProgressView(value: downloadFraction)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isDownloading {
                Text("Install in progress. This engine becomes active when download and compile finish.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if installed {
                if !isCurrent {
                    MAYNButton("Use engine", role: .primary) {
                        useModel(modelID)
                    }
                }
            } else {
                MAYNButton("Download and use", role: .primary) {
                    downloadModel(modelID, selectWhenReady: true)
                }
            }

            if installed, !isDownloading {
                HStack(spacing: 8) {
                    MAYNButton("Show file") {
                        showModelInFinder(modelID)
                    }
                    MAYNButton("Delete...", role: .destructive) {
                        deleteModel(modelID)
                    }
                }
            }

            if let status = modelDownloadStatus[modelID] {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func voiceCloudEngineDetailPane(for modelID: VoiceCloudASRModelID) -> some View {
        let provider = modelID.providerKind
        let hasKey = hasUsableCloudAPIKey(for: provider)
        let isCurrent = currentEngineID == .cloud(modelID)
        let isProviderTesting = isTestingCloud && cloudSetupProviderKind == provider
        let statusText: String
        let statusKind: StatusPill.Kind

        if isProviderTesting {
            statusText = "Testing"
            statusKind = .progress
        } else if isCurrent, hasKey {
            statusText = "In use"
            statusKind = .success
        } else if hasKey {
            statusText = "API key ready"
            statusKind = .neutral
        } else {
            statusText = "API key required"
            statusKind = .warning
        }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cloud engine")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                StatusPill(text: statusText, kind: statusKind)
            }

            Text(modelID.title)
                .font(.title3.weight(.semibold))
            Text(modelID.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                StatusPill(text: provider.label, kind: .neutral)
                StatusPill(text: hasKey ? "Key entered" : "Needs key", kind: hasKey ? .neutral : .warning)
                StatusPill(text: VoiceLanguageModePresentation.title(for: cloudLanguageHint), kind: .neutral)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Details")
                    .font(.callout.weight(.semibold))
                Label("Requires network access.", systemImage: "network")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("Sends audio to \(provider.label) using your API key.", systemImage: "icloud")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("Respects the same language hint used by dictation.", systemImage: "globe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            MAYNSecureField(
                placeholder: provider.apiKeyPlaceholder,
                text: cloudAPIKeyBinding(for: provider),
                width: MAYNControlMetrics.wideTextFieldWidth
            )

            if hasKey {
                MAYNButton("Use engine", role: .primary) {
                    selectCloudModel(modelID)
                }
            } else {
                MAYNButton("Configure API key", role: .primary) {
                    selectCloudModel(modelID)
                }
            }

            HStack(spacing: 8) {
                MAYNButton(isProviderTesting ? "Testing..." : "Test connection") {
                    cloudSetupProviderKind = provider
                    cloudModelID = modelID
                    testCloudConnection()
                }
                .disabled(isProviderTesting)
            }

            if cloudSetupProviderKind == provider, let cloudStatusMessage {
                Text(cloudStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func voiceExperimentalEngineDetailPane(for descriptorID: String) -> some View {
        let descriptor = VoiceEngineCatalogPresentation.experimentalDescriptor(for: descriptorID)
        let title = descriptor?.title ?? "Experimental engine"
        let subtitle = descriptor?.subtitle ?? "Planned recognizer. Not available in the current build."
        let requirement = descriptor?.requiresOSLabel ?? "Unavailable"

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Experimental")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                StatusPill(text: "Unavailable", kind: .warning)
            }

            Text(title)
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                StatusPill(text: requirement, kind: .neutral)
                StatusPill(text: "Advanced picker only", kind: .neutral)
            }

            Text("This engine remains visible for planning and migration checks, but it is not selectable for dictation in this release.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            MAYNSettingsRow(
                title: "Cleanup model",
                subtitle: cleanupRowSubtitle,
                belowSubtitle: {
                    AnyView(StatusPill(text: cleanupSavedSelectionLine, kind: .neutral))
                }
            ) {
                MAYNButton("Change...") {
                    openCleanupPicker()
                }
            }
            .accessibilityLabel("Cleanup model")
            .accessibilityValue(cleanupAccessibilitySummary)

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
        let cleanupSettings = controller.voiceCleanupSettings()
        cleanupEnabled = cleanupSettings.isEnabled
        cleanupProvider = cleanupSettings.provider
        cleanupModel = cleanupSettings.model
        cleanupBaseURLString = cleanupSettings.baseURLString
        cleanupAPIKey = controller.voiceCleanupAPIKey(for: cleanupSettings.provider)
        cleanupTimeoutSeconds = cleanupSettings.timeoutSeconds
        cleanupLatencyPolicy = cleanupSettings.latencyPolicy
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
                subtitle: VoiceTranscriptHistoryMetadata.line(for: transcript),
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

    private var recognitionEngineSingleTag: String {
        switch asrProviderKind {
        case .local:
            selectedASRModelID.title
        case .groq, .elevenLabs, .openAITranscribe, .deepgram:
            cloudModelID.title
        }
    }

    private var recognitionEngineRowSubtitle: String {
        switch asrProviderKind {
        case .local:
            selectedASRModelID.subtitle
        case .groq, .elevenLabs, .openAITranscribe, .deepgram:
            cloudModelID.subtitle
        }
    }

    /// Saved cleanup provider and resolved model name (uses defaults when the model field is empty).
    private var cleanupSavedSelectionLine: String {
        let settings = cleanupVoiceSettingsSnapshot
        return "\(cleanupProvider.label) · \(settings.effectiveModel)"
    }

    private var cleanupVoiceSettingsSnapshot: VoiceCleanupSettings {
        VoiceCleanupSettings(
            isEnabled: cleanupEnabled,
            provider: cleanupProvider,
            model: cleanupModel,
            baseURLString: cleanupBaseURLString,
            timeoutSeconds: cleanupTimeoutSeconds,
            latencyPolicy: cleanupLatencyPolicy
        )
    }

    private var cleanupRowSubtitle: String {
        if cleanupEnabled {
            "Tap the row to pick provider, model, keys, and timeout. Runs after recognition while AI cleanup is on."
        } else {
            "AI cleanup is off; local cleanup and dictionary still apply."
        }
    }

    private var cleanupAccessibilitySummary: String {
        "\(cleanupSavedSelectionLine). \(cleanupRowSubtitle)"
    }

    private var cleanupSettingsDraft: VoiceCleanupSettings {
        cleanupVoiceSettingsSnapshot
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

    private func cloudAPIKeyBinding(for providerKind: VoiceASRProviderKind) -> Binding<String> {
        Binding(
            get: { cloudAPIKeys[providerKind] ?? "" },
            set: { cloudAPIKeys[providerKind] = $0 }
        )
    }

    private func hasUsableCloudAPIKey(for providerKind: VoiceASRProviderKind) -> Bool {
        VoiceASRModelSelectionState.canSelectCloudModel(apiKey: cloudAPIKeys[providerKind] ?? "")
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
