import Core
import SwiftUI

private enum DownloadFormatTab: String, CaseIterable, SegmentedTabDestination {
    case video
    case audio

    var title: String {
        switch self {
        case .video: "Video"
        case .audio: "Audio"
        }
    }

    var symbolName: String {
        switch self {
        case .video: "play.rectangle"
        case .audio: "waveform"
        }
    }
}

struct DownloadFormatSheet: View {
    let sourceURL: String
    let metadata: VideoMetadata?
    let isRefiningResolutions: Bool
    let onClose: () -> Void
    let onDownload: (DownloadFormatPreset) -> Void

    @State private var selectedTab: DownloadFormatTab = .video
    @State private var selectedPreset: DownloadFormatPreset = .videoBest

    private static let standardVideoPresets: [DownloadFormatPreset] = [
        .video1080, .video720, .video360, .video240, .video144,
    ]

    private var videoPresets: [DownloadFormatPreset] {
        var result: [DownloadFormatPreset] = [.videoBest]
        let available = metadata?.availableHeights ?? []
        if available.isEmpty {
            result += Self.standardVideoPresets
        } else {
            for preset in Self.standardVideoPresets where available.contains(preset.qualityHeight) {
                result.append(preset)
            }
        }
        return result
    }

    private var audioPresets: [DownloadFormatPreset] { [.audio320, .audio128] }

    private var activePresets: [DownloadFormatPreset] {
        selectedTab == .video ? videoPresets : audioPresets
    }

    private var controlsLocked: Bool {
        metadata == nil || isRefiningResolutions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                thumbnailView
                metadataView
            }

            FunctionSegmentedTabStrip(selection: selectedTab, size: .control) { nextTab in
                selectedTab = nextTab
                syncSelectedPreset(for: nextTab)
            }
            .disabled(controlsLocked)

            VStack(alignment: .leading, spacing: 8) {
                MAYNDropdown(
                    selection: $selectedPreset,
                    options: activePresets,
                    title: { $0.displayLabel },
                    width: 412
                )
                .disabled(controlsLocked)

                if metadata == nil {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading video details…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if isRefiningResolutions {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Checking exact resolutions…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Spacer()
                MAYNButton("Cancel", action: onClose)
                MAYNButton("Download", role: .primary) {
                    onDownload(selectedPreset)
                }
                .disabled(controlsLocked)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(MAYNTheme.window)
        .onAppear {
            syncSelectedPreset(for: selectedTab)
        }
        .onChange(of: metadata?.availableHeights) { _, _ in
            syncSelectedPreset(for: selectedTab)
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        Group {
            if let urlStr = metadata?.thumbnailURL, !urlStr.isEmpty, let url = URL(string: urlStr) {
                DownloadPickerThumbnailImage(url: url)
            } else {
                thumbnailPlaceholder
            }
        }
        .frame(width: 132, height: 74)
        .clipShape(RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            MAYNTheme.elevated
            if metadata == nil {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "play.rectangle").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var metadataView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let metadata {
                Text(metadata.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                Text(metadata.channelName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if metadata.durationSeconds > 0 {
                    Text(DownloadPickerDurationFormatting.format(metadata.durationSeconds))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(MAYNTheme.elevated)
                    .frame(width: 220, height: 13)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(MAYNTheme.elevated)
                    .frame(width: 100, height: 11)
            }
            Text(sourceURL)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func syncSelectedPreset(for tab: DownloadFormatTab) {
        let presets = tab == .video ? videoPresets : audioPresets
        if presets.contains(selectedPreset) {
            return
        }
        selectedPreset = presets.first ?? .videoBest
    }
}
