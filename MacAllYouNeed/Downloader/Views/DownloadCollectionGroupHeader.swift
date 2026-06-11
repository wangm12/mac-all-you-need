import Core
import SwiftUI

struct DownloadCollectionGroupHeader: View {
    let group: DownloadCollectionGrouping.Group
    let progress: Double
    let speedText: String?
    let etaText: String?
    let isExpanded: Bool
    let showsPauseAll: Bool
    let showsResumeAll: Bool
    let onToggleExpanded: () -> Void
    let onPauseAll: () -> Void
    let onResumeAll: () -> Void
    let onDelete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onToggleExpanded) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                ZStack {
                    RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [MAYNTheme.elevated, MAYNTheme.window.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
                        )
                    Image(systemName: group.kind == .douyinProfile ? "folder" : "rectangle.stack")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(group.title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Text(group.kind == .douyinProfile ? "Folder" : "Collection")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(MAYNTheme.elevated, in: Capsule())
                            .overlay(Capsule().stroke(MAYNTheme.subtleBorder, lineWidth: 1))
                    }
                    Text(DownloadCollectionGrouping.groupSubtitle(for: group))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 9) {
                    HStack(spacing: 8) {
                        Text("\(group.completedCount)/\(group.totalCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if let speedText {
                            Text(speedText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let etaText {
                            Text(etaText)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    VStack(alignment: .trailing, spacing: 6) {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(MAYNTheme.divider.opacity(0.9))
                                Capsule()
                                    .fill(MAYNTheme.progress)
                                    .frame(width: max(2, geometry.size.width * progress))
                            }
                        }
                        .frame(width: 132, height: 4)
                        Text(progress >= 1 ? "Completed" : "\(Int((progress * 100).rounded()))%")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

            }

            HStack(spacing: 10) {
                summaryChip(title: "Total videos", value: "\(group.totalCount)")
                summaryChip(title: "Completed", value: "\(group.completedCount)")
                summaryChip(title: "Progress", value: "\(Int((progress * 100).rounded()))%")
                Spacer(minLength: 8)
                if showsResumeAll {
                    DownloadIconButton(symbolName: "play.fill", accessibilityLabel: "Resume all", action: onResumeAll)
                }
                if showsPauseAll {
                    DownloadIconButton(symbolName: "pause.fill", accessibilityLabel: "Pause all", action: onPauseAll)
                }
                DownloadIconButton(symbolName: "trash", role: .destructive, accessibilityLabel: "Remove collection", action: onDelete)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MAYNTheme.window.opacity(0.35))
            )
        }
        .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [MAYNTheme.elevated, MAYNTheme.elevated.opacity(0.94)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggleExpanded)
        .animation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion), value: isExpanded)
    }

    private func summaryChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(minWidth: 76, alignment: .leading)
    }
}

struct DownloadCollectionDeleteSheet: View {
    let title: String
    let itemCount: Int
    let onCancel: () -> Void
    let onRemoveListOnly: () -> Void
    let onRemoveWithFiles: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(MAYNTheme.danger.opacity(0.09))
                    .frame(width: 54, height: 54)
                Circle()
                    .strokeBorder(MAYNTheme.danger.opacity(0.35), lineWidth: 1)
                    .frame(width: 54, height: 54)
                Image(systemName: "trash")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MAYNTheme.danger)
            }

            VStack(spacing: 7) {
                Text("Remove collection")
                    .font(.title3.weight(.semibold))
                Text(title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text("\(itemCount) item\(itemCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Choose whether to keep downloaded files on disk or delete them as well.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                MAYNButton("Remove from list only", role: .primary, action: onRemoveListOnly)
                    .frame(maxWidth: .infinity)
                MAYNButton("Delete files and remove", role: .destructive, action: onRemoveWithFiles)
                    .frame(maxWidth: .infinity)
                MAYNButton("Cancel", action: onCancel)
                    .frame(maxWidth: .infinity)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(26)
        .frame(width: 380)
        .background(MAYNTheme.window)
    }
}
