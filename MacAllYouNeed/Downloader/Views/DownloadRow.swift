import Core
import Platform
import SwiftUI

// MARK: - Presentation helpers

enum DownloadStatePresentation {
    static func badgeText(for state: DownloadState, isMerging: Bool) -> String {
        switch state {
        case .running: isMerging ? "Merging" : "Downloading"
        case .paused: "Paused"
        case .queued: "Queued"
        case .completed: "Done"
        case .failed: "Failed"
        }
    }

    static func pillKind(for state: DownloadState) -> StatusPill.Kind {
        switch state {
        case .completed: .success
        case .failed: .danger
        case .paused: .warning
        case .running: .progress
        case .queued: .neutral
        }
    }
}

enum DownloadJobRowActionPresentation {
    static func primaryActionTitle(for state: DownloadState) -> String {
        switch state {
        case .running: "Pause"
        case .paused: "Resume"
        case .queued: "Cancel"
        case .completed: "Open Folder"
        case .failed: "Retry"
        }
    }

    static func primaryActionSymbol(for state: DownloadState) -> String {
        switch state {
        case .running: "pause.fill"
        case .paused: "play.fill"
        case .queued: "xmark"
        case .completed: "folder"
        case .failed: "arrow.counterclockwise"
        }
    }

    static func isRetryable(_ state: DownloadState) -> Bool {
        state == .failed
    }
}

enum DownloadJobRowHoverPresentation {
    static let missingErrorHelpText = "No captured yt-dlp error is available for this failed download. Retry the row to capture fresh stderr details."

    static func rowHelpText(for model: DownloadJobRowModel) -> String? {
        guard model.state == .failed else { return nil }
        let trimmed = model.errorTooltip?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? missingErrorHelpText : trimmed
    }

    static func inlineErrorLineLimit(isHovering: Bool) -> Int? {
        isHovering ? nil : 1
    }
}

// MARK: - Row model

struct DownloadJobRowModel: Identifiable {
    let id: RecordID
    let sourceURL: String
    let title: String
    let subtitle: String
    let thumbnailURL: URL?
    let state: DownloadState
    let statusText: String
    let phase: String
    let progress: Double
    let speedText: String?
    let etaText: String?
    let inlineError: String?
    let errorTooltip: String?
    let destinationPath: String?

    var statusPillKind: StatusPill.Kind {
        DownloadStatePresentation.pillKind(for: state)
    }

    init(record: DownloadRecord, progress: DownloadProgress?, statusText: String?) {
        id = record.id
        sourceURL = record.url
        title = record.videoTitle ?? record.title
        subtitle = Self.subtitle(for: record)
        thumbnailURL = record.thumbnailURL.flatMap(URL.init(string:))
        state = record.state
        let isMerging = Self.isMerging(statusText)
        self.statusText = DownloadStatePresentation.badgeText(for: record.state, isMerging: isMerging)
        phase = Self.phase(for: record, statusText: statusText, isMerging: isMerging)
        self.progress = Self.progressFraction(for: record, progress: progress)
        speedText = Self.speedText(for: progress)
        etaText = Self.etaText(for: progress, state: record.state)
        inlineError = Self.inlineError(for: record)
        errorTooltip = Self.inlineError(for: record)
        destinationPath = record.destinationPath
    }

    private static func isMerging(_ statusText: String?) -> Bool {
        let phase = statusText?.lowercased() ?? ""
        return phase.contains("merg") || phase.contains("remux")
    }

    private static func subtitle(for record: DownloadRecord) -> String {
        let parts: [String] = [record.channelName, record.durationSeconds.map(formatDuration)]
            .compactMap { $0 }
        guard !parts.isEmpty else { return record.url }
        return parts.joined(separator: " · ")
    }

    private static func phase(for record: DownloadRecord, statusText: String?, isMerging _: Bool) -> String {
        switch record.state {
        case .running:
            let trimmed = statusText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "Downloading" : trimmed
        case .paused:
            return "Paused; resume continues from partial file"
        case .queued:
            return "Waiting for an available slot"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed during extractor step"
        }
    }

    private static func progressFraction(for record: DownloadRecord, progress: DownloadProgress?) -> Double {
        if record.state == .completed { return 1 }
        if let progress {
            if let downloaded = progress.downloadedBytes, let total = progress.totalBytes, total > 0 {
                return clamped(Double(downloaded) / Double(total))
            }
            return clamped(progress.fraction)
        }
        if let total = record.bytesTotal, total > 0 {
            return clamped(Double(record.bytesDownloaded) / Double(total))
        }
        return 0
    }

    private static func speedText(for progress: DownloadProgress?) -> String? {
        guard let speed = progress?.speedBytesPerSec, speed > 0 else { return nil }
        return "\(ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file))/s"
    }

    private static func etaText(for progress: DownloadProgress?, state: DownloadState) -> String? {
        guard state == .running, let eta = progress?.etaSeconds, eta > 0 else { return nil }
        return String(format: "ETA %d:%02d", eta / 60, eta % 60)
    }

    private static func inlineError(for record: DownloadRecord) -> String? {
        guard record.state == .failed else { return nil }
        let trimmed = record.lastError?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
            : String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private static func clamped(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

// MARK: - Row view

struct DownloadJobRow: View {
    let model: DownloadJobRowModel
    let isSelected: Bool
    var isCompact = false
    let onTap: () -> Void
    let onPrimaryAction: () -> Void
    let onDelete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var thumbnailSize: CGSize {
        isCompact ? CGSize(width: 56, height: 34) : CGSize(width: 82, height: 48)
    }

    var body: some View {
        HStack(alignment: .center, spacing: isCompact ? 9 : 14) {
            thumbnailView

            VStack(alignment: .leading, spacing: isCompact ? 4 : 6) {
                titleLine
                if !model.subtitle.isEmpty {
                    Text(model.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                progressBar
                captionView
            }
        }
        .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
        .padding(.vertical, isCompact ? 8 : 12)
        .background(rowBackground)
        .overlay(MAYNDivider(), alignment: .bottom)
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                .stroke(isSelected ? MAYNTheme.focusRing : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .downloadRowHelp(DownloadJobRowHoverPresentation.rowHelpText(for: model))
        .onTapGesture { onTap() }
        .onHover { isHovering = $0 }
        .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isHovering)
        .animation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion), value: model.progress)
    }

    private var titleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            StatusPill(text: model.statusText.uppercased(), kind: model.statusPillKind)
            Text(model.title)
                .font(isCompact ? .caption.weight(.semibold) : .callout.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 6)
            if !isCompact {
                actionButtons
            }
        }
    }

    private var thumbnailView: some View {
        Group {
            if let thumbnailURL = model.thumbnailURL {
                AsyncImage(url: thumbnailURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    thumbnailPlaceholder(symbol: "photo")
                }
            } else if URLDetector.videoBearingURL(in: model.sourceURL) == nil {
                thumbnailPlaceholder(symbol: "link.circle")
            } else {
                thumbnailPlaceholder(symbol: "play.rectangle")
            }
        }
        .frame(width: thumbnailSize.width, height: thumbnailSize.height)
        .clipShape(RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }

    private func thumbnailPlaceholder(symbol: String) -> some View {
        ZStack {
            MAYNTheme.elevated
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(MAYNTheme.divider)
                Capsule()
                    .fill(progressColor)
                    .frame(width: max(2, geometry.size.width * model.progress))
            }
        }
        .frame(height: isCompact ? 2 : 3)
    }

    private var captionView: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(model.phase)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .downloadRowHelp(DownloadJobRowHoverPresentation.rowHelpText(for: model))
                if let speedText = model.speedText {
                    Text("· \(speedText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let etaText = model.etaText, !isCompact {
                    Text(etaText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            if let inlineError = model.inlineError {
                Text(inlineError)
                    .font(.caption)
                    .foregroundStyle(MAYNTheme.danger)
                    .lineLimit(DownloadJobRowHoverPresentation.inlineErrorLineLimit(isHovering: isHovering))
                    .truncationMode(.tail)
                    .help(DownloadJobRowHoverPresentation.rowHelpText(for: model) ?? inlineError)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            DownloadIconButton(
                symbolName: DownloadJobRowActionPresentation.primaryActionSymbol(for: model.state),
                role: model.state == .failed ? .destructive : .secondary,
                accessibilityLabel: DownloadJobRowActionPresentation.primaryActionTitle(for: model.state),
                action: onPrimaryAction
            )
            DownloadIconButton(
                symbolName: "trash",
                role: .destructive,
                accessibilityLabel: "Delete",
                action: onDelete
            )
        }
    }

    private var rowBackground: Color {
        if isSelected { return MAYNTheme.selected }
        if isHovering { return MAYNTheme.hover }
        return Color.clear
    }

    private var progressColor: Color {
        switch model.state {
        case .completed: MAYNTheme.success
        case .failed: MAYNTheme.danger
        case .paused: MAYNTheme.warning
        case .running: MAYNTheme.progress
        case .queued: .secondary
        }
    }
}

// MARK: - Help modifier

private struct DownloadRowHelpModifier: ViewModifier {
    let helpText: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let helpText {
            content.help(helpText)
        } else {
            content
        }
    }
}

extension View {
    func downloadRowHelp(_ helpText: String?) -> some View {
        modifier(DownloadRowHelpModifier(helpText: helpText))
    }
}

// MARK: - Icon button

struct DownloadIconButton: View {
    enum Role {
        case secondary
        case destructive
    }

    let symbolName: String
    var role: Role = .secondary
    let accessibilityLabel: String
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: MAYNControlMetrics.controlHeight, height: MAYNControlMetrics.controlHeight)
                .background(background, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .scaleEffect(isPressed && !reduceMotion ? 0.985 : 1)
        .onHover { isHovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isHovering)
        .animation(MAYNMotion.fastAnimation(reduceMotion: reduceMotion), value: isPressed)
    }

    private var foreground: Color {
        role == .destructive ? MAYNTheme.danger : .secondary
    }

    private var background: Color {
        if isPressed { return MAYNTheme.elevatedPressed }
        if isHovering { return MAYNTheme.elevatedHover }
        return Color.clear
    }
}
