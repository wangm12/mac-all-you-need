import Core
import FluidAudio
import SwiftUI

/// Onboarding sub-step for the Voice feature. Lets the user pick an ASR provider
/// (cloud BYOK or local runtimes) and optionally kick off local model downloads.
///
/// Mirrors the essential first-run pieces from `VoiceSettingsView`'s ASR section,
/// without the microphone picker, dictionary, cleanup, or history rows — those are
/// all available from Settings → Voice after the wizard finishes.
struct VoiceProviderSetupView: View {
    let controller: AppController
    @State private var providerKind: VoiceASRProviderKind
    @State private var selectedLocalModelID: VoiceASRModelID
    @State private var cloudModelID: VoiceCloudASRModelID
    @State private var cloudAPIKeys: [VoiceASRProviderKind: String]
    @State private var modelDownloadFractions: [VoiceASRModelID: Double] = [:]
    @State private var modelDownloadStatus: [VoiceASRModelID: String] = [:]
    @State private var downloadingModelID: VoiceASRModelID?

    init(controller: AppController) {
        self.controller = controller
        let asr = VoiceASRSettingsStore.load()
        let cloud = VoiceCloudASRSettingsStore.load()
        _providerKind = State(initialValue: asr.providerKind)
        _selectedLocalModelID = State(initialValue: asr.modelID)
        _cloudModelID = State(
            initialValue: asr.providerKind.isCloud
                ? cloud.modelID(for: asr.providerKind)
                : cloud.modelID
        )
        let cloudKeys = Dictionary(
            uniqueKeysWithValues: VoiceASRProviderKind.allCases
                .filter(\.isCloud)
                .map { ($0, controller.cloudASRAPIKey(for: $0)) }
        )
        _cloudAPIKeys = State(initialValue: cloudKeys)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Provider selector
            Picker("ASR Provider", selection: $providerKind) {
                ForEach(VoiceASRProviderKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 200)
            .onChange(of: providerKind) { _, newKind in
                applyProviderSelection(newKind)
            }

            MAYNDivider()

            switch providerKind {
            case .local:
                localSection
            case .groq, .elevenLabs, .openAITranscribe, .deepgram:
                cloudSection
            }

            Text("You can refine these later from Settings → Voice.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Cloud section

    private var cloudSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(providerKind.label)
                .font(.headline)
            Text(providerKind.subtitle)
                .font(.caption).foregroundStyle(.secondary)
            MAYNSecureField(placeholder: providerKind.apiKeyPlaceholder, text: cloudAPIKeyBinding, width: 360)
            MAYNDropdown(
                selection: $cloudModelID,
                options: availableCloudModels,
                title: { $0.title },
                width: MAYNControlMetrics.widePickerWidth
            )
            .onChange(of: cloudModelID) { _, newModelID in
                providerKind = newModelID.providerKind
                applyCloudSettings()
            }
            MAYNButton("Save key", role: .primary) {
                applyCloudSettings()
            }
        }
    }

    // MARK: - Local section

    private var localSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Local ASR")
                .font(.headline)
            Text("On-device, private. A one-time model download is required for each local runtime.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(VoiceModelCatalog.localASRModels) { descriptor in
                if let modelID = descriptor.localASRModelID {
                    localModelRow(modelID)
                } else {
                    VoiceUnsupportedASRModelRow(descriptor: descriptor)
                }
            }
        }
    }

    private func localModelRow(_ modelID: VoiceASRModelID) -> some View {
        let isDownloaded = VoiceModelManager.isLocalASRModelInstalled(modelID)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(modelID.title).font(.callout)
                if let status = modelDownloadStatus[modelID] {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isDownloaded {
                StatusPill(text: "Ready", kind: .success)
                if selectedLocalModelID != modelID {
                    MAYNButton("Use") {
                        selectedLocalModelID = modelID
                        applyLocalSelection()
                    }
                }
            } else if downloadingModelID == modelID {
                ProgressView(value: modelDownloadFractions[modelID] ?? 0)
                    .frame(width: 120)
                Text("\(Int((modelDownloadFractions[modelID] ?? 0) * 100))%")
                    .font(.caption)
            } else {
                MAYNButton("Download") { startDownload(modelID) }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private func applyProviderSelection(_ kind: VoiceASRProviderKind) {
        let asr = VoiceASRSettingsStore.load()
        let cloud = VoiceCloudASRSettingsStore.load()
        if kind.isCloud {
            cloudModelID = cloud.modelID(for: kind)
        }
        try? controller.applyVoiceASRProviderSettings(
            asrSettings: asr.updating(providerKind: kind),
            cloudSettings: cloud.updating(modelID: cloud.modelID(for: kind)),
            cloudAPIKey: cloudAPIKeys[kind] ?? ""
        )
    }

    private func applyCloudSettings() {
        let asr = VoiceASRSettingsStore.load()
        let cloud = VoiceCloudASRSettings(modelID: cloudModelID, languageHint: VoiceCloudASRSettingsStore.load().languageHint)
        try? controller.applyVoiceASRProviderSettings(
            asrSettings: asr.updating(providerKind: cloudModelID.providerKind),
            cloudSettings: cloud,
            cloudAPIKey: cloudAPIKeys[cloudModelID.providerKind] ?? ""
        )
    }

    private func applyLocalSelection() {
        let asr = VoiceASRSettings(
            modelID: selectedLocalModelID,
            languageHint: VoiceASRSettingsStore.load().languageHint,
            providerKind: .local
        )
        try? controller.applyVoiceASRProviderSettings(
            asrSettings: asr,
            cloudSettings: VoiceCloudASRSettingsStore.load(),
            cloudAPIKey: cloudAPIKeys[cloudModelID.providerKind] ?? ""
        )
    }

    private var availableCloudModels: [VoiceCloudASRModelID] {
        VoiceCloudASRModelID.allCases.filter { $0.providerKind == providerKind }
    }

    private var cloudAPIKeyBinding: Binding<String> {
        Binding(
            get: { cloudAPIKeys[providerKind] ?? "" },
            set: { cloudAPIKeys[providerKind] = $0 }
        )
    }

    private func startDownload(_ modelID: VoiceASRModelID) {
        downloadingModelID = modelID
        modelDownloadStatus[modelID] = "Downloading…"
        Task {
            do {
                try await VoiceModelManager.downloadLocalASRModel(
                    modelID,
                    progressHandler: { progress in
                        Task { @MainActor in
                            modelDownloadFractions[modelID] = progress.fractionCompleted
                        }
                    }
                )
                await MainActor.run {
                    modelDownloadStatus[modelID] = nil
                    downloadingModelID = nil
                    modelDownloadFractions[modelID] = nil
                    selectedLocalModelID = modelID
                    applyLocalSelection()
                }
            } catch {
                await MainActor.run {
                    modelDownloadStatus[modelID] = "Failed: \(error.localizedDescription)"
                    downloadingModelID = nil
                }
            }
        }
    }
}
