import Core
import SwiftUI

/// Shared row for voice transcript history in the main window and Command Center.
struct VoiceTranscriptHistoryRowView: View {
    enum Surface {
        /// Ellipsis menu: retry, download audio, delete.
        case main
        /// Inline copy + retry only (no download / delete).
        case commandCenter
    }

    let transcript: VoiceTranscript
    let surface: Surface
    let isSelected: Bool
    let isRetrying: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onRetry: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private var hasAudio: Bool {
        transcript.audioPath != nil
    }

    private var isSuccessfulTranscript: Bool {
        transcript.status == .success
    }

    private var showsCopyAction: Bool {
        isSuccessfulTranscript
    }

    private var showsRetryAction: Bool {
        !isSuccessfulTranscript
    }

    private var accessoryOpacity: Double {
        if surface == .commandCenter { return 1 }
        return (isHovering || isSelected) ? 1 : 0
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayText)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                Text(metadataLine)
                    .font(.caption)
                    .foregroundStyle(
                        MAYNSelectionLabelStyle.subtitle(
                            isSelected: isSelected,
                            scheme: colorScheme
                        )
                    )
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsCopyAction {
                DownloadIconButton(
                    symbolName: "doc.on.doc",
                    role: .secondary,
                    accessibilityLabel: "Copy transcript",
                    action: onCopy
                )
                .help("Copy transcript")
                .opacity(accessoryOpacity)
                .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isHovering)
                .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isSelected)
            }

            switch surface {
            case .main:
                VoiceTranscriptRowMenu(
                    hasAudio: hasAudio,
                    showsRetry: showsRetryAction,
                    retryEnabled: !isRetrying,
                    onRetry: onRetry,
                    onDownload: onDownload,
                    onDelete: onDelete
                )
                .opacity(accessoryOpacity)
                .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isHovering)
                .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isSelected)
            case .commandCenter:
                if showsRetryAction {
                    DownloadIconButton(
                        symbolName: "arrow.clockwise",
                        role: .secondary,
                        accessibilityLabel: "Retry transcription",
                        action: onRetry
                    )
                    .disabled(!hasAudio || isRetrying)
                    .help(
                        hasAudio
                            ? (isRetrying ? "Retrying..." : "Retry transcription")
                            : "Audio recording wasn't saved for this transcript"
                    )
                }
            }
        }
        .padding(.horizontal, surface == .commandCenter ? 10 : 14)
        .padding(.vertical, surface == .commandCenter ? 9 : 10)
        .frame(minHeight: surface == .commandCenter ? 58 : 62)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if surface == .main {
                rowBackground
            }
        }
        .maynSelectionBackground(
            isSelected: surface == .commandCenter && isSelected,
            isHovering: isHovering,
            shape: .rounded(surface == .commandCenter ? 14 : 10)
        )
        .foregroundStyle(MAYNTheme.textPrimary(colorScheme))
        .padding(.horizontal, surface == .commandCenter ? 6 : 0)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                if showsCopyAction { onCopy() }
            }
        )
        .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isHovering)
        .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isSelected)
        .onHover { isHovering = $0 }
    }

    private var displayText: String {
        MainVoiceTranscriptHistoryPresentation.displayText(transcript)
    }

    private var metadataLine: String {
        VoiceTranscriptHistoryMetadata.detailLine(for: transcript)
    }

    private var rowBackground: Color {
        if isSelected { return MAYNTheme.selected }
        if isHovering { return MAYNTheme.hover }
        return .clear
    }
}
