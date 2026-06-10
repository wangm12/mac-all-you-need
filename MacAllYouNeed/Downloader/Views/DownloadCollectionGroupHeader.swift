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
        HStack(spacing: 12) {
            Button(action: onToggleExpanded) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }
            .buttonStyle(.plain)

            ZStack {
                RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius)
                    .fill(MAYNTheme.elevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius)
                            .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
                    )
                Image(systemName: group.kind == .douyinProfile ? "folder" : "list.video")
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(group.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(DownloadCollectionGrouping.groupSubtitle(for: group))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(MAYNTheme.divider)
                        Capsule()
                            .fill(MAYNTheme.progress)
                            .frame(width: max(2, geometry.size.width * progress))
                    }
                }
                .frame(width: 96, height: 4)

                HStack(spacing: 6) {
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
            }

            HStack(spacing: 6) {
                if showsResumeAll {
                    DownloadIconButton(symbolName: "play.fill", accessibilityLabel: "Resume all", action: onResumeAll)
                }
                if showsPauseAll {
                    DownloadIconButton(symbolName: "pause.fill", accessibilityLabel: "Pause all", action: onPauseAll)
                }
                DownloadIconButton(symbolName: "trash", role: .destructive, accessibilityLabel: "Remove collection", action: onDelete)
            }
        }
        .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
        .padding(.vertical, 10)
        .background(MAYNTheme.elevated)
        .overlay(MAYNDivider(), alignment: .bottom)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggleExpanded)
        .animation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion), value: isExpanded)
    }
}

struct DownloadCollectionDeleteSheet: View {
    let title: String
    let itemCount: Int
    let onCancel: () -> Void
    let onRemoveListOnly: () -> Void
    let onRemoveWithFiles: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(MAYNTheme.subtleBorder)
                        .frame(width: 48, height: 48)
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title3)
                        .foregroundStyle(MAYNTheme.danger)
                }
                Text("Remove collection")
                    .font(.title3.weight(.semibold))
                Text("\(title) · \(itemCount) item\(itemCount == 1 ? "" : "s")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Choose whether to keep downloaded files on disk or delete them as well.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                MAYNButton("Remove from list only", role: .primary, action: onRemoveListOnly)
                    .frame(maxWidth: .infinity)
                MAYNButton("Delete files and remove", role: .destructive, action: onRemoveWithFiles)
                    .frame(maxWidth: .infinity)
                MAYNButton("Cancel", action: onCancel)
                    .frame(maxWidth: .infinity)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 360)
        .background(MAYNTheme.window)
    }
}
