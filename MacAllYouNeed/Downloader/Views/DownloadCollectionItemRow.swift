import Core
import SwiftUI

struct DownloadCollectionItemRow: View {
    let record: DownloadRecord
    let model: DownloadJobRowModel
    let isSelected: Bool
    var isCompact: Bool = false
    var showsThumbnail: Bool = true
    var showsDivider: Bool = true
    let onTap: () -> Void
    let onPrimaryAction: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var thumbnailSize: CGSize {
        isCompact ? CGSize(width: 72, height: 44) : CGSize(width: 94, height: 58)
    }

    var body: some View {
        HStack(alignment: .center, spacing: isCompact ? 10 : 14) {
            thumbnailView
            titleBlock
                .frame(maxWidth: .infinity, alignment: .leading)
            if !isCompact {
                fileMeta
                    .frame(width: 106, alignment: .trailing)
            }
            rowActions
        }
        .padding(.horizontal, MAYNControlMetrics.rowControlSpacing)
        .padding(.vertical, isCompact ? 11 : 14)
        .background(rowBackground)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(MAYNTheme.divider)
                    .frame(height: 1)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                .stroke(isSelected ? MAYNTheme.focusRing : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .downloadRowHelp(DownloadJobRowHoverPresentation.rowHelpText(for: model))
        .onTapGesture { onTap() }
        .onHover { isHovering = $0 }
        .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isHovering)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if showsThumbnail {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    DownloadThumbnailView(record: record, placeholderSymbol: "photo")
                }
                .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                .clipShape(RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                        .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
                )

                if let duration = durationLabel {
                    Text(duration)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(6)
                }
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: isCompact ? 4 : 7) {
            Text(model.title)
                .font(isCompact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .lineLimit(1)

            metaLine

            if model.state != .completed {
                activeProgressLine
            }

            if let inlineError = model.inlineError {
                Text(inlineError)
                    .font(.caption)
                    .foregroundStyle(MAYNTheme.danger)
                    .lineLimit(DownloadJobRowHoverPresentation.inlineErrorLineLimit(isHovering: isHovering))
            }
        }
    }

    @ViewBuilder
    private var metaLine: some View {
        HStack(spacing: 0) {
            ForEach(Array(metaParts.enumerated()), id: \.offset) { index, part in
                if index > 0 {
                    Text(" · ")
                        .foregroundStyle(.secondary)
                }
                if part.isStatus {
                    inlineStatus(text: part.text)
                } else {
                    Text(part.text)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.caption)
        .lineLimit(1)
    }

    @ViewBuilder
    private var activeProgressLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.progress > 0 || model.state == .running {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(MAYNTheme.divider)
                        Capsule()
                            .fill(progressColor)
                            .frame(
                                width: DownloadCollectionPresentation.progressFillWidth(
                                    totalWidth: geometry.size.width,
                                    progress: model.progress
                                )
                            )
                    }
                }
                .frame(height: 3)
            }

            HStack(spacing: 5) {
                Text(model.phase)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let speedText = model.speedText {
                    Text("· \(speedText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let etaText = model.etaText {
                    Text(etaText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
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

    private var rowBackground: Color {
        if isSelected { return MAYNTheme.selected.opacity(0.35) }
        if isHovering { return MAYNTheme.elevatedHover.opacity(0.45) }
        return Color.clear
    }

    private var progressColor: Color {
        switch model.state {
        case .completed: MAYNTheme.success
        case .failed: Color.secondary.opacity(0.35)
        case .paused: Color.secondary.opacity(0.45)
        default: MAYNTheme.progress
        }
    }

    private var durationLabel: String? {
        guard let seconds = model.durationSeconds, seconds > 0 else { return nil }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
            : String(format: "%d:%02d", minutes, remainingSeconds)
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

    private struct MetaPart {
        let text: String
        let isStatus: Bool
    }

    private var metaParts: [MetaPart] {
        var parts: [MetaPart] = []
        if let channel = channelLabel {
            parts.append(MetaPart(text: channel, isStatus: false))
        }
        if let ext = fileExtensionLabel {
            parts.append(MetaPart(text: ext, isStatus: false))
        }
        parts.append(MetaPart(text: statusLabel, isStatus: model.state == .completed))
        return parts
    }

    private var channelLabel: String? {
        let channel = model.subtitle.components(separatedBy: " · ").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !channel.isEmpty, channel != model.sourceURL else { return nil }
        return channel
    }

    private var statusLabel: String {
        switch model.state {
        case .completed: "Completed"
        case .running: model.statusText
        case .paused: "Paused"
        case .queued: "Queued"
        case .failed: "Failed"
        }
    }

    private var fileExtensionLabel: String? {
        guard let path = model.destinationPath, !path.contains("%(") else { return nil }
        let ext = URL(fileURLWithPath: path).pathExtension
        guard !ext.isEmpty else { return nil }
        return ext.uppercased()
    }

    private func thumbnailPlaceholder(symbol: String) -> some View {
        ZStack {
            MAYNTheme.elevated
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private func inlineStatus(text: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(MAYNTheme.success)
                .frame(width: 6, height: 6)
            Text(text)
                .foregroundStyle(MAYNTheme.success)
        }
        .font(.caption.weight(.semibold))
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
