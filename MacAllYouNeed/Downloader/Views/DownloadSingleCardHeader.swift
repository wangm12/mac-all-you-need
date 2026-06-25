import Core
import SwiftUI

struct DownloadSingleCardHeader: View {
    let record: DownloadRecord
    let model: DownloadJobRowModel
    let locationLabel: String
    let isCompact: Bool
    let onPrimaryAction: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var artSize: CGFloat { isCompact ? 48 : 58 }
    private var horizontalPadding: CGFloat { MAYNControlMetrics.rowControlSpacing }
    private var verticalPadding: CGFloat { isCompact ? 14 : 16 }
    private var status: (label: String, pillKind: StatusPill.Kind) {
        DownloadCollectionPresentation.singleStatus(for: record)
    }

    private var completedCount: Int {
        model.state == .completed ? 1 : 0
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnailArt
            VStack(alignment: .leading, spacing: 10) {
                titleLine
                Text(DownloadCollectionPresentation.singleCompactMetaLine(for: record, location: locationLabel))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                progressBlock
                if !isCompact, model.speedText != nil || model.etaText != nil {
                    speedLine
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !isCompact {
                fileMeta
                    .frame(width: 106, alignment: .trailing)
                rowActions
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .onHover { isHovering = $0 }
        .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isHovering)
        .animation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion), value: record.state)
    }

    private var thumbnailArt: some View {
        DownloadThumbnailView(record: record)
            .frame(width: artSize, height: artSize)
            .clipShape(RoundedRectangle(cornerRadius: isCompact ? 14 : 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: isCompact ? 14 : 16, style: .continuous)
                    .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
            )
    }

    private var titleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(model.title)
                .font(isCompact ? .callout.weight(.semibold) : .headline.weight(.semibold))
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            StatusPill(text: status.label, kind: status.pillKind)
        }
    }

    private var progressBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(completedCount) of 1 completed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(Int((model.progress * 100).rounded()))%")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(MAYNTheme.divider.opacity(0.9))
                    Capsule()
                        .fill(progressBarColor)
                        .frame(
                            width: DownloadCollectionPresentation.progressFillWidth(
                                totalWidth: geometry.size.width,
                                progress: model.progress
                            )
                        )
                }
            }
            .frame(height: 6)

            if model.state != .completed {
                Text(model.phase)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let inlineError = model.inlineError {
                Text(inlineError)
                    .font(.caption)
                    .foregroundStyle(MAYNTheme.danger)
                    .lineLimit(2)
            }
        }
    }

    private var fileMeta: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let sizeText {
                Text(sizeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(Self.formattedModified(model.modified))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var rowActions: some View {
        HStack(spacing: 2) {
            if let symbol = primaryActionSymbol {
                DownloadIconButton(
                    symbolName: symbol,
                    accessibilityLabel: primaryActionLabel,
                    action: onPrimaryAction
                )
            }
            DownloadIconButton(
                symbolName: "folder",
                accessibilityLabel: "Show in Finder",
                action: onReveal
            )
            if isHovering {
                DownloadIconButton(
                    symbolName: "trash",
                    role: .secondary,
                    accessibilityLabel: "Remove from List",
                    action: onDelete
                )
            }
        }
    }

    private var primaryActionSymbol: String? {
        switch model.state {
        case .paused: "play.fill"
        case .failed: "arrow.clockwise"
        case .running: "pause.fill"
        case .queued: "xmark"
        case .completed: nil
        }
    }

    private var primaryActionLabel: String {
        switch model.state {
        case .paused: "Resume"
        case .failed: "Retry"
        case .running: "Pause"
        case .queued: "Cancel"
        case .completed: "Open"
        }
    }

    private var sizeText: String? {
        guard let path = model.destinationPath, !path.contains("%(") else { return nil }
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path),
           let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
           let size = values.fileSize
        {
            return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        }
        return nil
    }

    private var speedLine: some View {
        HStack(spacing: 6) {
            if let speedText = model.speedText {
                Text(speedText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let etaText = model.etaText {
                Text(etaText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var progressBarColor: Color {
        switch model.state {
        case .completed:
            MAYNTheme.success
        case .running:
            MAYNTheme.progress
        case .paused:
            Color.secondary.opacity(0.45)
        case .failed:
            Color.secondary.opacity(0.35)
        case .queued:
            Color.secondary.opacity(0.35)
        }
    }

    private static func formattedModified(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "'Today' HH:mm"
            return formatter.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "'Yesterday' HH:mm"
            return formatter.string(from: date)
        }
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
