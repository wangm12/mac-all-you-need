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
    let onClose: () -> Void
    let onDownload: (DownloadFormatPreset) -> Void

    @State private var selectedTab: DownloadFormatTab = .video

    // Standard presets in priority order (after Best available)
    private static let standardVideoPresets: [DownloadFormatPreset] = [
        .video1080, .video720, .video360, .video240, .video144,
    ]

    private var videoPresets: [DownloadFormatPreset] {
        var result: [DownloadFormatPreset] = [.videoBest]
        let available = metadata?.availableHeights ?? []
        if available.isEmpty {
            // Metadata not loaded yet, or site doesn't expose heights — show standard list
            result += Self.standardVideoPresets
        } else {
            // Only show presets whose height is actually available
            for preset in Self.standardVideoPresets where available.contains(preset.qualityHeight) {
                result.append(preset)
            }
        }
        return result
    }

    private var audioPresets: [DownloadFormatPreset] { [.audio320, .audio128] }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                thumbnailView
                metadataView
            }

            FunctionSegmentedTabStrip(selection: selectedTab, size: .control) { nextTab in
                selectedTab = nextTab
            }

            VStack(spacing: 8) {
                let presets = selectedTab == .video ? videoPresets : audioPresets
                ForEach(presets, id: \.rawValue) { preset in
                    Button(action: { onDownload(preset) }) {
                        HStack(spacing: 10) {
                            Text(preset.displayLabel)
                                .font(.callout.weight(.medium))
                            Spacer(minLength: 12)
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(MAYNTheme.elevated, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius)
                                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                // Spinner row while video metadata is still loading
                if selectedTab == .video, metadata == nil {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Fetching available resolutions…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                }
            }

            HStack {
                Spacer()
                MAYNButton("Cancel", action: onClose)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(MAYNTheme.window)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        Group {
            if let urlStr = metadata?.thumbnailURL, !urlStr.isEmpty, let url = URL(string: urlStr) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    thumbnailPlaceholder
                }
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
                // Skeleton while loading
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
}
