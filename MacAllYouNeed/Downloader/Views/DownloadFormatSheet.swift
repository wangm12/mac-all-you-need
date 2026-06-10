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
    let metadata: VideoMetadata
    let onClose: () -> Void
    let onDownload: (DownloadFormatPreset) -> Void

    @State private var selectedTab: DownloadFormatTab = .video

    private var videoPresets: [DownloadFormatPreset] {
        [.video1080, .video720, .video360, .video240, .video144]
    }

    private var audioPresets: [DownloadFormatPreset] {
        [.audio320, .audio128]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                thumbnail
                VStack(alignment: .leading, spacing: 6) {
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
                    Text(sourceURL)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            FunctionSegmentedTabStrip(
                selection: selectedTab,
                size: .control
            ) { nextTab in
                selectedTab = nextTab
            }

            VStack(spacing: 8) {
                ForEach(currentPresets, id: \.rawValue) { preset in
                    MAYNButton(preset.displayLabel, role: .secondary) {
                        onDownload(preset)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack {
                Spacer()
                MAYNButton("Cancel", action: onClose)
            }
        }
        .padding(24)
        .frame(width: 430)
        .background(MAYNTheme.window)
    }

    private var currentPresets: [DownloadFormatPreset] {
        selectedTab == .video ? videoPresets : audioPresets
    }

    @ViewBuilder
    private var thumbnail: some View {
        Group {
            if let url = URL(string: metadata.thumbnailURL), !metadata.thumbnailURL.isEmpty {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: 120, height: 68)
        .clipShape(RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius))
    }

    private var placeholder: some View {
        ZStack {
            MAYNTheme.elevated
            Image(systemName: "play.rectangle")
                .foregroundStyle(.secondary)
        }
    }
}
