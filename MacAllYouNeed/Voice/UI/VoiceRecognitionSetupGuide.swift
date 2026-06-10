import SwiftUI

struct VoiceRecognitionSetupGuide: View {
    let controller: AppController
    var footerText: String = "You can refine these later from Voice settings."
    var showsHeaderCopy: Bool = true
    var showsLanguageRow: Bool = true
    var showsExactSelectionRow: Bool = true

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
    @State private var appliedEngineID: VoiceEngineID
    @State private var pickerSelectedEngineID: VoiceEngineID
    @State private var pickerFilter: VoiceEnginePickerFilter = .all
    @State private var pickerSearchText = ""

    init(
        controller: AppController,
        footerText: String = "You can refine these later from Voice settings.",
        showsHeaderCopy: Bool = true,
        showsLanguageRow: Bool = true,
        showsExactSelectionRow: Bool = true
    ) {
        self.controller = controller
        self.footerText = footerText
        self.showsHeaderCopy = showsHeaderCopy
        self.showsLanguageRow = showsLanguageRow
        self.showsExactSelectionRow = showsExactSelectionRow

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
        let initialEngineID = VoiceEngineCatalogPresentation.currentEngineID(
            providerKind: asr.providerKind,
            selectedLocalModelID: asr.modelID,
            selectedCloudModelID: asr.providerKind.isCloud
                ? cloud.modelID(for: asr.providerKind)
                : cloud.modelID
        )
        _appliedEngineID = State(initialValue: initialEngineID)
        _pickerSelectedEngineID = State(initialValue: initialEngineID)
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
                    title: "Recommended engine",
                    subtitle: engineSelectionDetail(appliedEngineID),
                    belowSubtitle: { AnyView(selectedEngineBadge) }
                ) {
                    MAYNButton("Change...") {
                        openEnginePicker()
                    }
                }
                .id(appliedEngineID)

                if showsExactSelectionRow {
                    MAYNDivider()
                    MAYNSettingsRow(
                        title: "Exact selection",
                        subtitle: exactSelectionDetail,
                        belowSubtitle: { AnyView(selectedEngineBadge) }
                    ) {
                        MAYNButton("Choose exact engine...") {
                            openEnginePicker()
                        }
                    }
                    .id("exact-\(appliedEngineID.id)")
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
                currentEngineID: appliedEngineID,
                entries: VoiceEngineCatalogPresentation.pickerEntries(),
                onClose: closeEnginePicker
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
        let isCurrent = appliedEngineID == .local(modelID)
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
        let isCurrent = appliedEngineID == .cloud(modelID)
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

            if !isCurrent {
                if hasKey {
                    MAYNButton("Use engine", role: .primary) {
                        selectCloudModel(modelID)
                    }
                } else {
                    MAYNButton("Configure API key", role: .primary) {
                        selectCloudModel(modelID)
                    }
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

    private var selectedEngineEntry: VoiceEngineListEntry? {
        VoiceEngineCatalogPresentation.pickerEntries().first { $0.id == appliedEngineID }
    }

    private var selectedEngineBadge: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(engineTitle(appliedEngineID))
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                StatusPill(text: "In use", kind: .success)
                StatusPill(text: engineKindLabel(appliedEngineID), kind: .neutral)
            }
        }
    }

    private var exactSelectionDetail: String {
        if let entry = selectedEngineEntry, entry.subtitle != engineTitle(appliedEngineID) {
            return entry.subtitle
        }
        return engineSelectionDetail(appliedEngineID)
    }

    private func engineSelectionDetail(_ engineID: VoiceEngineID) -> String {
        switch engineID {
        case let .local(modelID):
            return "\(modelID.subtitle) On-device recognition."
        case let .cloud(modelID):
            return modelID.subtitle
        case .experimental:
            return "Experimental engine · not available for dictation in this build"
        }
    }

    private func engineKindLabel(_ engineID: VoiceEngineID) -> String {
        switch engineID {
        case .local:
            "Local"
        case let .cloud(modelID):
            modelID.providerKind.label
        case .experimental:
            "Experimental"
        }
    }

    private func openEnginePicker() {
        syncPresentationFromStores()
        pickerSelectedEngineID = appliedEngineID
        pickerFilter = .all
        pickerSearchText = ""
        isShowingEnginePicker = true
    }

    private func closeEnginePicker() {
        syncPresentationFromStores()
        isShowingEnginePicker = false
    }

    private func selectLocalModel(_ modelID: VoiceASRModelID) {
        selectedASRModelID = modelID
        asrProviderKind = VoiceASRModelSelectionState.providerKindAfterSelectingLocalModel()
        controller.applyVoiceASRSettings(
            VoiceASRSettings(
                modelID: modelID,
                languageHint: VoiceASRSettingsStore.load().languageHint,
                providerKind: .local
            )
        )
        appliedEngineID = .local(modelID)
        pickerSelectedEngineID = .local(modelID)
        modelDownloadStatus[modelID] = "Selected for future dictation."
        syncPresentationFromStores()
    }

    private func selectCloudModel(_ modelID: VoiceCloudASRModelID) {
        let provider = VoiceASRModelSelectionState.providerKindAfterSelectingCloudModel(modelID)
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
            appliedEngineID = .cloud(modelID)
            pickerSelectedEngineID = .cloud(modelID)
            cloudStatusMessage = "\(provider.label) selected."
            syncPresentationFromStores()
        } catch {
            cloudStatusMessage = error.localizedDescription
        }
    }

    private func syncPresentationFromStores() {
        let asr = VoiceASRSettingsStore.load()
        let cloud = VoiceCloudASRSettingsStore.load()
        selectedASRModelID = asr.modelID
        asrProviderKind = asr.providerKind
        cloudLanguageHint = cloud.languageHint
        if asr.providerKind.isCloud {
            cloudModelID = cloud.modelID(for: asr.providerKind)
            cloudSetupProviderKind = asr.providerKind
        } else {
            cloudModelID = cloud.modelID
        }
        appliedEngineID = VoiceEngineCatalogPresentation.currentEngineID(
            providerKind: asrProviderKind,
            selectedLocalModelID: selectedASRModelID,
            selectedCloudModelID: cloudModelID
        )
    }

    private func engineTitle(_ engineID: VoiceEngineID) -> String {
        switch engineID {
        case let .local(modelID):
            modelID.title
        case let .cloud(modelID):
            modelID.title
        case let .experimental(id):
            VoiceEngineCatalogPresentation.experimentalDescriptor(for: id)?.title ?? "Experimental engine"
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
                    appliedEngineID = .cloud(cloudSettings.modelID)
                    pickerSelectedEngineID = .cloud(cloudSettings.modelID)
                    syncPresentationFromStores()
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
