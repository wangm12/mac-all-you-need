import Core
import FluidAudio
import SwiftUI

struct VoiceASRStepView: View {
    @State private var selectedModelID = VoiceASRSettingsStore.load().modelID
    @State private var isPreparing = false
    @State private var downloadFraction: Double?
    @State private var statusMessage = "Choose a local recognition model. Missing models download before dictation uses them."

    private let primaryOptions = VoiceModelCatalog.localASRModels

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose speech recognition")
                .font(.title)
                .bold()
            Text("Audio stays local by default. Qwen3 covers mixed Chinese/English; Parakeet is faster for English and supported European languages.")
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(primaryOptions) { descriptor in
                    if let modelID = descriptor.localASRModelID {
                        modelButton(modelID)
                    } else {
                        VoiceUnsupportedASRModelCard(descriptor: descriptor)
                    }
                }
            }
            HStack {
                MAYNButton(isPreparing ? "Downloading..." : actionTitle(for: selectedModelID), role: .primary) {
                    selectModel(selectedModelID)
                }
                .disabled(isPreparing)
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let downloadFraction {
                ProgressView(value: downloadFraction)
            }
            Spacer()
        }
    }

    private func modelButton(_ modelID: VoiceASRModelID) -> some View {
        Button {
            selectModel(modelID)
        } label: {
            VoiceASRModelOnboardingCard(
                modelID: modelID,
                isSelected: selectedModelID == modelID,
                isDownloaded: isDownloaded(modelID),
                isPreparing: isPreparing && selectedModelID == modelID,
                downloadFraction: selectedModelID == modelID ? downloadFraction : nil
            )
        }
        .buttonStyle(.plain)
        .disabled(isPreparing)
    }

    private func selectModel(_ modelID: VoiceASRModelID) {
        selectedModelID = modelID
        guard !isDownloaded(modelID) else {
            saveSelectedModel(modelID)
            statusMessage = "\(modelID.title) is ready and selected."
            return
        }
        prepareModel(modelID)
    }

    private func prepareModel(_ modelID: VoiceASRModelID) {
        guard !isPreparing else { return }
        isPreparing = true
        downloadFraction = 0
        statusMessage = "Downloading \(modelID.title) into the local model cache..."
        Task {
            do {
                _ = try await VoiceModelManager.downloadLocalASRModel(modelID) { progress in
                    Task { @MainActor in
                        downloadFraction = progress.fractionCompleted
                        statusMessage = Self.describe(progress, modelID: modelID)
                    }
                }
                await MainActor.run {
                    saveSelectedModel(modelID)
                    statusMessage = "\(modelID.title) is ready and selected."
                    downloadFraction = 1
                    isPreparing = false
                }
            } catch {
                await MainActor.run {
                    statusMessage = error.localizedDescription
                    downloadFraction = nil
                    isPreparing = false
                }
            }
        }
    }

    private func saveSelectedModel(_ modelID: VoiceASRModelID) {
        var settings = VoiceASRSettingsStore.load()
        settings.modelID = modelID
        VoiceASRSettingsStore.save(settings)
    }

    private func isDownloaded(_ modelID: VoiceASRModelID) -> Bool {
        VoiceModelManager.isLocalASRModelInstalled(modelID)
    }

    private func actionTitle(for modelID: VoiceASRModelID) -> String {
        isDownloaded(modelID) ? "Use selected model" : "Download & Use"
    }

    private static func describe(_ progress: DownloadUtils.DownloadProgress, modelID: VoiceASRModelID) -> String {
        switch progress.phase {
        case .listing:
            "Listing \(modelID.title) files..."
        case let .downloading(completedFiles, totalFiles):
            "Downloading \(modelID.title) files \(completedFiles)/\(totalFiles)..."
        case let .compiling(modelName):
            "Compiling \(modelName)..."
        }
    }
}

struct VoiceASRModelOnboardingCard: View {
    let modelID: VoiceASRModelID
    let isSelected: Bool
    let isDownloaded: Bool
    let isPreparing: Bool
    let downloadFraction: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(modelID.title)
                    .font(.headline)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            Text(modelID.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                StatusPill(text: modelID.diskLabel, kind: .neutral)
                StatusPill(text: statusText, kind: statusKind)
            }
            if let downloadFraction {
                ProgressView(value: downloadFraction)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MAYNTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? MAYNTheme.strongBorder : MAYNTheme.subtleBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var statusText: String {
        if isPreparing { return "Downloading" }
        if isDownloaded { return "Downloaded" }
        return "Not installed"
    }

    private var statusKind: StatusPill.Kind {
        if isPreparing { return .progress }
        if isDownloaded { return .success }
        return .warning
    }
}
