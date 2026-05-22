import SwiftUI

struct VoiceRecognitionSetupGuide: View {
    let controller: AppController
    var footerText: String = "You can refine these later from Voice settings."
    var showsHeaderCopy: Bool = true
    var showsLanguageRow: Bool = true

    @State private var selectedASRModelID: VoiceASRModelID
    @State private var asrProviderKind: VoiceASRProviderKind
    @State private var cloudModelID: VoiceCloudASRModelID
    @State private var cloudLanguageHint: VoiceASRLanguageHint
    @State private var cloudAPIKeys: [VoiceASRProviderKind: String]
    @State private var cloudSetupProviderKind: VoiceASRProviderKind
    @State private var cloudStatusMessage: String?
    @State private var isTestingCloud = false
    @State private var modelDownloadStatus: [VoiceASRModelID: String] = [:]
    @State private var modelDownloadFractions: [VoiceASRModelID: Double] = [:]
    @State private var downloadingModelID: VoiceASRModelID?
    @State private var isShowingEnginePicker = false
    @State private var pickerSelectedEngineID: VoiceEngineID
    @State private var pickerFilter: VoiceEnginePickerFilter = .all
    @State private var pickerSearchText = ""

    init(
        controller: AppController,
        footerText: String = "You can refine these later from Voice settings.",
        showsHeaderCopy: Bool = true,
        showsLanguageRow: Bool = true
    ) {
        self.controller = controller
        self.footerText = footerText
        self.showsHeaderCopy = showsHeaderCopy
        self.showsLanguageRow = showsLanguageRow

        let asr = VoiceASRSettingsStore.load()
        let cloud = VoiceCloudASRSettingsStore.load()
        _selectedASRModelID = State(initialValue: asr.modelID)
        _asrProviderKind = State(initialValue: asr.providerKind)
        _cloudModelID = State(
            initialValue: asr.providerKind.isCloud
                ? cloud.modelID(for: asr.providerKind)
                : cloud.modelID
        )
        _cloudLanguageHint = State(initialValue: cloud.languageHint)
        let cloudKeys = Dictionary(
            uniqueKeysWithValues: VoiceASRProviderKind.allCases
                .filter(\.isCloud)
                .map { ($0, controller.cloudASRAPIKey(for: $0)) }
        )
        _cloudAPIKeys = State(initialValue: cloudKeys)
        _cloudSetupProviderKind = State(initialValue: asr.providerKind.isCloud ? asr.providerKind : cloud.modelID.providerKind)
        _pickerSelectedEngineID = State(
            initialValue: VoiceEngineCatalogPresentation.currentEngineID(
                providerKind: asr.providerKind,
                selectedLocalModelID: asr.modelID,
                selectedCloudModelID: asr.providerKind.isCloud
                    ? cloud.modelID(for: asr.providerKind)
                    : cloud.modelID
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHeaderCopy {
                Text("Choose recognition engine")
                    .font(.title3.weight(.semibold))
                Text("Use local on-device recognition by default, or configure exact cloud and experimental engines.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            MAYNSection(title: "Recognition") {
                MAYNSettingsRow(
                    title: "Recognition engine",
                    subtitle: recognitionSummary
                ) {
                    MAYNButton("Change...") {
                        openEnginePicker()
                    }
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Exact selection",
                    subtitle: "Advanced selection for exact local, cloud, and experimental recognizers."
                ) {
                    MAYNButton("Choose exact engine...") {
                        openEnginePicker()
                    }
                }
                if showsLanguageRow {
                    MAYNDivider()
                    MAYNSettingsRow(
                        title: "Dictation language",
                        subtitle: "Auto-detect is best for mixed Chinese and English."
                    ) {
                        MAYNDropdown(
                            selection: $cloudLanguageHint,
                            options: Array(VoiceASRLanguageHint.allCases),
                            title: VoiceLanguageModePresentation.title,
                            width: MAYNControlMetrics.widePickerWidth
                        )
                        .onChange(of: cloudLanguageHint) { _, hint in
                            applyCloudLanguageHint(hint)
                        }
                    }
                }
            }

            if !footerText.isEmpty {
                Text(footerText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $isShowingEnginePicker) {
            VoiceEnginePickerSheet(
                selectedEngineID: $pickerSelectedEngineID,
                filter: $pickerFilter,
                searchText: $pickerSearchText,
                currentEngineID: currentEngineID,
                entries: VoiceEngineCatalogPresentation.pickerEntries(),
                onDone: { isShowingEnginePicker = false }
            ) { engineID in
                detailPane(for: engineID)
            }
        }
    }

    @ViewBuilder
    private func detailPane(for engineID: VoiceEngineID) -> some View {
        switch engineID {
        case let .local(modelID):
            localDetailPane(for: modelID)
        case let .cloud(modelID):
            cloudDetailPane(for: modelID)
        case let .experimental(id):
            experimentalDetailPane(for: id)
        }
    }

    private func localDetailPane(for modelID: VoiceASRModelID) -> some View {
        let installed = VoiceModelManager.isLocalASRModelInstalled(modelID)
        let isCurrent = currentEngineID == .local(modelID)
        let isDownloading = downloadingModelID == modelID
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
            }

            if let progress = modelDownloadFractions[modelID], isDownloading {
                ProgressView(value: progress)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isDownloading {
                Text("Install in progress. This engine becomes active when download and compile finish.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if installed {
                if !isCurrent {
                    MAYNButton("Use engine", role: .primary) {
                        selectLocalModel(modelID)
                    }
                }
            } else {
                MAYNButton("Download and use", role: .primary) {
                    startDownload(modelID, selectWhenReady: true)
                }
            }

            if let status = modelDownloadStatus[modelID] {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func cloudDetailPane(for modelID: VoiceCloudASRModelID) -> some View {
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

            MAYNButton(isProviderTesting ? "Testing..." : "Test connection") {
                cloudSetupProviderKind = provider
                cloudModelID = modelID
                testCloudConnection()
            }
            .disabled(isProviderTesting)

            if cloudSetupProviderKind == provider, let cloudStatusMessage {
                Text(cloudStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func experimentalDetailPane(for descriptorID: String) -> some View {
        let descriptor = VoiceEngineCatalogPresentation.experimentalDescriptor(for: descriptorID)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Experimental")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                StatusPill(text: "Unavailable", kind: .warning)
            }

            Text(descriptor?.title ?? "Experimental engine")
                .font(.title3.weight(.semibold))
            Text(descriptor?.subtitle ?? "Planned recognizer. Not available in the current build.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let requiresOSLabel = descriptor?.requiresOSLabel {
                StatusPill(text: requiresOSLabel, kind: .neutral)
            }
            Text("This engine remains visible for planning and migration checks, but it is not selectable for dictation in this release.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var currentEngineID: VoiceEngineID {
        VoiceEngineCatalogPresentation.currentEngineID(
            providerKind: asrProviderKind,
            selectedLocalModelID: selectedASRModelID,
            selectedCloudModelID: cloudModelID
        )
    }

    private var recognitionSummary: String {
        switch asrProviderKind {
        case .local:
            selectedASRModelID.title
        case .groq, .elevenLabs, .openAITranscribe, .deepgram:
            cloudModelID.title
        }
    }

    private func openEnginePicker() {
        pickerSelectedEngineID = currentEngineID
        pickerFilter = .all
        pickerSearchText = ""
        isShowingEnginePicker = true
    }

    private func selectLocalModel(_ modelID: VoiceASRModelID) {
        selectedASRModelID = modelID
        asrProviderKind = .local
        controller.applyVoiceASRSettings(
            VoiceASRSettings(
                modelID: modelID,
                languageHint: VoiceASRSettingsStore.load().languageHint,
                providerKind: .local
            )
        )
        modelDownloadStatus[modelID] = "Selected for future dictation."
    }

    private func selectCloudModel(_ modelID: VoiceCloudASRModelID) {
        let provider = modelID.providerKind
        cloudSetupProviderKind = provider
        guard hasUsableCloudAPIKey(for: provider) else {
            cloudStatusMessage = "Add \(provider.apiKeyLabel) before selecting this cloud model."
            return
        }

        cloudModelID = modelID
        asrProviderKind = provider
        do {
            try controller.applyVoiceASRProviderSettings(
                asrSettings: VoiceASRSettings(
                    modelID: selectedASRModelID,
                    languageHint: VoiceASRSettingsStore.load().languageHint,
                    providerKind: provider
                ),
                cloudSettings: VoiceCloudASRSettings(
                    modelID: modelID,
                    languageHint: cloudLanguageHint
                ),
                cloudAPIKey: cloudAPIKeys[provider] ?? ""
            )
            cloudStatusMessage = "\(provider.label) selected."
        } catch {
            cloudStatusMessage = error.localizedDescription
        }
    }

    private func startDownload(_ modelID: VoiceASRModelID, selectWhenReady: Bool) {
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
                            modelDownloadFractions[modelID] = progress.fractionCompleted
                            modelDownloadStatus[modelID] = VoiceSettingsModelDownloadPresenter.describe(progress)
                        }
                    }
                )
                await MainActor.run {
                    downloadingModelID = nil
                    modelDownloadFractions[modelID] = nil
                    modelDownloadStatus[modelID] = "Downloaded."
                    if selectWhenReady {
                        selectLocalModel(modelID)
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

    private func applyCloudLanguageHint(_ hint: VoiceASRLanguageHint) {
        let cloudSettings = VoiceCloudASRSettings(modelID: cloudModelID, languageHint: hint)
        controller.applyCloudASRSettings(cloudSettings)
        if asrProviderKind == .local {
            let localSettings = VoiceASRSettings(
                modelID: selectedASRModelID,
                languageHint: hint,
                providerKind: .local
            )
            controller.applyVoiceASRSettings(localSettings)
        }
    }

    private func testCloudConnection() {
        isTestingCloud = true
        cloudStatusMessage = "Connecting..."
        let provider = cloudSetupProviderKind
        let cloudSettings = VoiceCloudASRSettings(
            modelID: cloudModelID.providerKind == provider ? cloudModelID : VoiceCloudASRModelID.defaultModel(for: provider),
            languageHint: cloudLanguageHint
        )
        let key = cloudAPIKeys[provider] ?? ""

        Task {
            let result = await controller.testCloudASRSettings(
                cloudSettings,
                providerKind: provider,
                apiKey: key
            )
            await MainActor.run {
                cloudStatusMessage = result
                if result.localizedCaseInsensitiveContains("succeeded"),
                   VoiceASRModelSelectionState.canSelectCloudModel(apiKey: key)
                {
                    cloudModelID = cloudSettings.modelID
                    asrProviderKind = provider
                    try? controller.applyVoiceASRProviderSettings(
                        asrSettings: VoiceASRSettings(
                            modelID: selectedASRModelID,
                            languageHint: VoiceASRSettingsStore.load().languageHint,
                            providerKind: provider
                        ),
                        cloudSettings: cloudSettings,
                        cloudAPIKey: key
                    )
                }
                isTestingCloud = false
            }
        }
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
