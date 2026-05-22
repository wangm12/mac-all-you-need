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
        MAYNSection(title: "Models") {
            MAYNSettingsRow(
                title: "Recognition model",
                subtitle: recognitionModelSummary
            ) {
                MAYNButton("Open Models", action: onOpenModels)
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

// MARK: - Cloud model row

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

// MARK: - Local model title line

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

// MARK: - Size tag

struct VoiceASRModelSizeTag: View {
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
