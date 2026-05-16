import Core
import FluidAudio
import SwiftUI

/// Onboarding sub-step for the Voice feature. Lets the user pick an ASR provider
/// (Groq cloud or local Qwen3) and optionally kick off the Qwen3 model download.
///
/// Mirrors the essential first-run pieces from `VoiceSettingsView`'s ASR section,
/// without the microphone picker, dictionary, cleanup, or history rows — those are
/// all available from Settings → Voice after the wizard finishes.
struct VoiceProviderSetupView: View {
    let controller: AppController
    @State private var providerKind: VoiceASRProviderKind
    @State private var selectedLocalModelID: VoiceASRModelID
    @State private var groqModelID: GroqASRModelID
    @State private var groqAPIKey: String
    @State private var modelDownloadFractions: [VoiceASRModelID: Double] = [:]
    @State private var modelDownloadStatus: [VoiceASRModelID: String] = [:]
    @State private var downloadingModelID: VoiceASRModelID?

    init(controller: AppController) {
        self.controller = controller
        let asr = VoiceASRSettingsStore.load()
        let groq = GroqASRSettingsStore.load()
        _providerKind = State(initialValue: asr.providerKind)
        _selectedLocalModelID = State(initialValue: asr.modelID)
        _groqModelID = State(initialValue: groq.modelID)
        _groqAPIKey = State(initialValue: controller.groqASRAPIKey())
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
            case .groq:
                cloudSection
            case .local:
                localSection
            }

            Text("You can refine these later from Settings → Voice.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Cloud section

    private var cloudSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Groq Whisper (cloud)")
                .font(.headline)
            Text("Fast, accurate, requires a Groq API key. Free tier available at console.groq.com.")
                .font(.caption).foregroundStyle(.secondary)
            MAYNSecureField(placeholder: "gsk_…  (Groq API key)", text: $groqAPIKey, width: 360)
            MAYNDropdown(
                selection: $groqModelID,
                options: Array(GroqASRModelID.allCases),
                title: { $0.title },
                width: MAYNControlMetrics.widePickerWidth
            )
            .onChange(of: groqModelID) { _, _ in applyGroqSettings() }
            MAYNButton("Save key", role: .primary) {
                applyGroqSettings()
            }
        }
    }

    // MARK: - Local section

    private var localSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Qwen3 ASR (local)")
                .font(.headline)
            Text("On-device, private. A one-time model download is required (~900 MB or 1.75 GB depending on model).")
                .font(.caption).foregroundStyle(.secondary)
            if #available(macOS 15, *) {
                ForEach(VoiceASRModelID.allCases, id: \.id) { modelID in
                    localModelRow(modelID)
                }
            } else {
                StatusPill(text: "Requires macOS 15+", kind: .warning)
                Text("Groq Whisper is available on all macOS versions and works well as an alternative.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @available(macOS 15, *)
    private func localModelRow(_ modelID: VoiceASRModelID) -> some View {
        let isDownloaded = Qwen3AsrModels.modelsExist(
            at: Qwen3AsrModels.defaultCacheDirectory(variant: modelID.variant)
        )
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
        let groq = GroqASRSettingsStore.load()
        try? controller.applyVoiceASRProviderSettings(
            asrSettings: asr.updating(providerKind: kind),
            groqSettings: groq,
            groqAPIKey: groqAPIKey
        )
    }

    private func applyGroqSettings() {
        let asr = VoiceASRSettingsStore.load()
        let groq = GroqASRSettings(modelID: groqModelID, languageHint: GroqASRSettingsStore.load().languageHint)
        try? controller.applyVoiceASRProviderSettings(
            asrSettings: asr,
            groqSettings: groq,
            groqAPIKey: groqAPIKey
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
            groqSettings: GroqASRSettingsStore.load(),
            groqAPIKey: groqAPIKey
        )
    }

    private func startDownload(_ modelID: VoiceASRModelID) {
        guard #available(macOS 15, *) else {
            modelDownloadStatus[modelID] = "Requires macOS 15 or later."
            return
        }
        downloadingModelID = modelID
        modelDownloadStatus[modelID] = "Downloading…"
        Task {
            do {
                try await Qwen3AsrModels.download(
                    variant: modelID.variant,
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
