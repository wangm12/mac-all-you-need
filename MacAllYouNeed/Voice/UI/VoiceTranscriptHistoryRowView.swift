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
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onRetry: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var hasAudio: Bool {
        transcript.audioPath != nil
    }

    private var accessoryOpacity: Double {
        if surface == .commandCenter { return 1 }
        return (isHovering || isSelected) ? 1 : 0
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(displayText)
                    .font(.callout)
                    .lineLimit(2)
                Text(metadataLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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

            switch surface {
            case .main:
                VoiceTranscriptRowMenu(
                    hasAudio: hasAudio,
                    onRetry: onRetry,
                    onDownload: onDownload,
                    onDelete: onDelete
                )
                .opacity(accessoryOpacity)
                .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isHovering)
                .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isSelected)
            case .commandCenter:
                DownloadIconButton(
                    symbolName: "arrow.clockwise",
                    role: .secondary,
                    accessibilityLabel: "Retry transcription",
                    action: onRetry
                )
                .disabled(!hasAudio)
                .help(
                    hasAudio
                        ? "Retry transcription"
                        : "Audio recording wasn't saved for this transcript"
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 62)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .simultaneousGesture(TapGesture(count: 2).onEnded { onCopy() })
        .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isHovering)
        .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isSelected)
        .onHover { isHovering = $0 }
    }

    private var displayText: String {
        MainVoiceTranscriptHistoryPresentation.displayText(transcript)
    }

    private var metadataLine: String {
        let time = CompactTimestamp.format(transcript.endedAt)
        let duration = formatDuration(ms: transcript.durationMs)
        return "\(time) · \(transcript.language.rawValue) · \(transcript.modelIdentifier) · \(duration)"
    }

    private func formatDuration(ms: Int) -> String {
        let seconds = Double(ms) / 1000.0
        if seconds < 60 { return String(format: "%.1f s", seconds) }
        let minutes = Int(seconds / 60)
        let remainder = Int(seconds.truncatingRemainder(dividingBy: 60))
        return "\(minutes)m \(remainder)s"
    }

    private var rowBackground: Color {
        if isSelected { return MAYNTheme.selected }
        if isHovering { return MAYNTheme.hover }
        return .clear
    }
}
