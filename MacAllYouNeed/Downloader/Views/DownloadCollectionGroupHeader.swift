import Core
import SwiftUI

struct DownloadCollectionGroupHeader: View {
    let group: DownloadCollectionGrouping.Group
    let progress: Double
    let speedText: String?
    let etaText: String?
    let locationLabel: String
    let collectionStatus: DownloadCollectionPresentation.CollectionStatus
    let hasActive: Bool
    let isExpanded: Bool
    let isCompact: Bool
    let showsPauseAll: Bool
    let showsResumeAll: Bool
    let onToggleExpanded: () -> Void
    let onOpenFolder: () -> Void
    let onPauseAll: () -> Void
    let onResumeAll: () -> Void
    let onRetryFailed: () -> Void
    let onCopySourceURL: () -> Void
    let onRemoveFromList: () -> Void
    let onMoveFilesToTrash: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var artSize: CGFloat { isCompact ? 48 : 58 }
    private var horizontalPadding: CGFloat { MAYNControlMetrics.rowControlSpacing }
    private var verticalPadding: CGFloat { isCompact ? 14 : 16 }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            disclosureButton
            collectionArt
            VStack(alignment: .leading, spacing: 10) {
                titleLine
                Text(DownloadCollectionPresentation.compactMetaLine(for: group, location: locationLabel))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                progressBlock
                if !isCompact {
                    actionRow
                }
                if !isCompact, speedText != nil || etaText != nil {
                    speedLine
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggleExpanded)
        .animation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion), value: isExpanded)
    }

    private var disclosureButton: some View {
        Button(action: onToggleExpanded) {
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private var collectionArt: some View {
        ZStack {
            RoundedRectangle(cornerRadius: isCompact ? 14 : 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [MAYNTheme.elevated, MAYNTheme.window.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: isCompact ? 14 : 16, style: .continuous)
                        .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
                )

            if group.kind == .douyinProfile {
                Image(systemName: "folder")
                    .font(.system(size: isCompact ? 16 : 18, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.secondary.opacity(0.55), lineWidth: 1.4)
                        .frame(width: isCompact ? 24 : 30, height: isCompact ? 16 : 20)
                        .offset(x: -4, y: -4)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.secondary.opacity(0.55), lineWidth: 1.4)
                        .frame(width: isCompact ? 24 : 30, height: isCompact ? 16 : 20)
                        .offset(x: 4, y: 4)
                }
            }
        }
        .frame(width: artSize, height: artSize)
    }

    private var titleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(group.title)
                .font(isCompact ? .callout.weight(.semibold) : .headline.weight(.semibold))
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            StatusPill(text: collectionStatus.label, kind: collectionStatus.pillKind)
        }
    }

    private var progressBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(group.completedCount) of \(group.totalCount) completed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(MAYNTheme.divider.opacity(0.9))
                    Capsule()
                        .fill(DownloadCollectionPresentation.progressBarColor(for: collectionStatus))
                        .frame(
                            width: DownloadCollectionPresentation.progressFillWidth(
                                totalWidth: geometry.size.width,
                                progress: progress
                            )
                        )
                }
            }
            .frame(height: 6)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            if let title = DownloadCollectionPresentation.primaryActionTitle(
                status: collectionStatus,
                showsPauseAll: showsPauseAll,
                showsResumeAll: showsResumeAll
            ) {
                MAYNButton(title, role: .secondary, height: 30) {
                    performPrimaryAction()
                }
            }

            MAYNButton(role: .secondary, height: 30, action: onOpenFolder) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.caption.weight(.semibold))
                    Text("Finder")
                        .font(.caption.weight(.semibold))
                }
            }

            Menu {
                Button("Copy Source URL", action: onCopySourceURL)
                Button("Open Collection Folder", action: onOpenFolder)
                Divider()
                Button("Remove from List", action: onRemoveFromList)
                Button("Move Files to Trash...", role: .destructive, action: onMoveFilesToTrash)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(MAYNTheme.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
                    )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var speedLine: some View {
        HStack(spacing: 6) {
            if let speedText {
                Text(speedText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let etaText {
                Text(etaText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func performPrimaryAction() {
        if showsPauseAll {
            onPauseAll()
        } else if collectionStatus == .failed {
            onRetryFailed()
        } else if showsResumeAll {
            onResumeAll()
        }
    }
}

struct DownloadCollectionExpandedToolbar: View {
    let itemFilter: DownloadCollectionItemFilter
    let onSelectFilter: (DownloadCollectionItemFilter) -> Void
    let onCopySourceURL: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Manage individual downloads in this collection.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            HStack(spacing: 6) {
                ForEach(DownloadCollectionItemFilter.allCases) { filter in
                    collectionFilterButton(filter)
                }
                MAYNButton("Copy Source URL", role: .secondary, height: 30, action: onCopySourceURL)
            }
        }
        .padding(.horizontal, MAYNControlMetrics.rowControlSpacing)
        .padding(.vertical, 12)
    }

    private func collectionFilterButton(_ filter: DownloadCollectionItemFilter) -> some View {
        Button {
            onSelectFilter(filter)
        } label: {
            Text(filter.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(itemFilter == filter ? Color.primary : Color.secondary)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    itemFilter == filter ? MAYNTheme.window : MAYNTheme.elevated.opacity(0.85),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct DownloadCollectionDeleteSheet: View {
    let title: String
    let itemLabel: String
    let statusLabel: String
    let locationLabel: String
    var initialDeleteFiles: Bool = false
    let onCancel: () -> Void
    let onConfirm: (_ deleteFiles: Bool) -> Void

    @State private var deleteFiles = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                header
                metadataBox
                optionCards
            }
            .padding(24)

            MAYNDivider()
                .padding(.leading, 0)

            footer
                .padding(24)
        }
        .frame(width: 480)
        .background(MAYNTheme.window)
        .onAppear {
            deleteFiles = initialDeleteFiles
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(MAYNTheme.danger.opacity(0.09))
                    .frame(width: 44, height: 44)
                Circle()
                    .strokeBorder(MAYNTheme.danger.opacity(0.35), lineWidth: 1)
                    .frame(width: 44, height: 44)
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(MAYNTheme.danger)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Remove \"\(title)\"?")
                    .font(.title3.weight(.semibold))
                Text("This removes the collection from Downloads. Choose what to do with downloaded files.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var metadataBox: some View {
        VStack(spacing: 10) {
            metadataRow(label: "Items", value: itemLabel)
            metadataRow(label: "Status", value: statusLabel)
            metadataRow(label: "Location", value: locationLabel, emphasizesValue: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MAYNTheme.elevated.opacity(0.65), in: RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }

    private func metadataRow(label: String, value: String, emphasizesValue: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(emphasizesValue ? .callout.weight(.semibold) : .callout)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }

    private var optionCards: some View {
        VStack(spacing: 10) {
            DownloadDeleteOptionCard(
                title: "Keep files on disk",
                badge: "Recommended",
                badgeKind: .neutral,
                description: "The downloaded files remain in their current folder.",
                isSelected: !deleteFiles
            ) {
                deleteFiles = false
            }

            DownloadDeleteOptionCard(
                title: "Move downloaded files to Trash",
                badge: "Frees disk space",
                badgeKind: .danger,
                description: "Files already saved for this collection will be moved to Trash.",
                isSelected: deleteFiles
            ) {
                deleteFiles = true
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            MAYNButton("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            if deleteFiles {
                MAYNButton("Move Files to Trash", role: .destructive) {
                    onConfirm(true)
                }
                .keyboardShortcut(.defaultAction)
            } else {
                MAYNButton("Remove from List", role: .primary) {
                    onConfirm(false)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct DownloadDeleteOptionCard: View {
    enum BadgeKind {
        case neutral
        case danger
    }

    let title: String
    let badge: String
    let badgeKind: BadgeKind
    let description: String
    let isSelected: Bool
    let onSelect: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? MAYNTheme.progress : .secondary.opacity(0.45))
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                        badgeView
                    }
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isHovering)
        .animation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion), value: isSelected)
    }

    private var badgeView: some View {
        Text(badge)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(badgeKind == .danger ? MAYNTheme.danger : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                (badgeKind == .danger ? MAYNTheme.danger : Color.secondary).opacity(0.10),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(
                    (badgeKind == .danger ? MAYNTheme.danger : MAYNTheme.subtleBorder).opacity(badgeKind == .danger ? 0.25 : 1),
                    lineWidth: 1
                )
            )
    }

    private var cardBackground: Color {
        if isSelected { return MAYNTheme.progress.opacity(0.08) }
        if isHovering { return MAYNTheme.elevatedHover.opacity(0.55) }
        return MAYNTheme.window
    }

    private var borderColor: Color {
        isSelected ? MAYNTheme.progress.opacity(0.55) : MAYNTheme.subtleBorder
    }
}
