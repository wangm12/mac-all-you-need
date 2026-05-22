import Core
import FluidAudio
import SwiftUI

// MARK: - Section View

struct VoiceProviderSection: View {
    let asrProviderKind: VoiceASRProviderKind
    let selectedASRModelID: VoiceASRModelID
    let cloudModelID: VoiceCloudASRModelID
    let onOpenModels: () -> Void

    var body: some View {
        MAYNSection(title: "Recognition") {
            MAYNSettingsRow(
                title: "Recognition engine",
                subtitle: recognitionModelSummary
            ) {
                MAYNButton("Choose recognition engine", action: onOpenModels)
            }
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
}

// MARK: - Download progress presenter

enum VoiceSettingsModelDownloadPresenter {
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

// MARK: - Language mode presentation

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
