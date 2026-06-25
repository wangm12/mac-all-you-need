import SwiftUI

struct DownloadsPageToolbar: View {
    let metrics: DownloadsPageMetrics
    @Binding var statusFilter: DownloadsStatusFilter
    @Binding var searchQuery: String
    let onOpenFolder: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                DownloadsStatusFilterChips(metrics: metrics, selection: $statusFilter)
                Spacer(minLength: 8)
                HStack(spacing: 10) {
                    DownloadsSearchField(query: $searchQuery)
                    MAYNButton("Open Downloads Folder", role: .primary, action: onOpenFolder)
                }
            }
        }
        .padding(.horizontal, MAYNControlMetrics.rowControlSpacing)
        .padding(.vertical, 14)
    }
}

struct DownloadsStatusFilterChips: View {
    let metrics: DownloadsPageMetrics
    @Binding var selection: DownloadsStatusFilter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            ForEach(DownloadsStatusFilter.allCases) { filter in
                DownloadsStatusChip(
                    title: chipTitle(for: filter),
                    dotColor: filter.dotColor,
                    isSelected: selection == filter
                ) {
                    selection = filter
                }
            }
        }
        .animation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion), value: selection)
    }

    private func chipTitle(for filter: DownloadsStatusFilter) -> String {
        let count: Int
        switch filter {
        case .all: count = metrics.totalVideos
        case .completed: count = metrics.completed
        case .active: count = metrics.activeCount
        case .paused: count = metrics.pausedCount
        case .failed: count = metrics.failedCount
        }
        return "\(filter.title) \(count)"
    }
}

private struct DownloadsStatusChip: View {
    let title: String
    let dotColor: DownloadsStatusDotColor
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(dotFill)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(chipBackground, in: Capsule())
            .overlay(Capsule().stroke(chipBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isHovering)
        .animation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion), value: isSelected)
    }

    private var dotFill: Color {
        switch dotColor {
        case .neutral: Color.secondary.opacity(0.55)
        case .success: MAYNTheme.success
        case .progress: MAYNTheme.progress
        case .warning: MAYNTheme.warning
        case .danger: MAYNTheme.danger
        }
    }

    private var chipBackground: Color {
        if isSelected { return MAYNTheme.window.opacity(0.95) }
        if isHovering { return MAYNTheme.elevatedHover.opacity(0.55) }
        return MAYNTheme.window.opacity(0.55)
    }

    private var chipBorder: Color {
        isSelected ? MAYNTheme.subtleBorder.opacity(1.2) : MAYNTheme.subtleBorder
    }
}

struct DownloadsSearchField: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.callout)
                .foregroundStyle(MAYNTheme.muted)
            TextField("Search downloads", text: $query)
                .textFieldStyle(.plain)
                .font(.callout)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MAYNTheme.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 250, height: MAYNControlMetrics.controlHeight + 8)
        .background(MAYNTheme.window.opacity(0.82), in: RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }
}

struct DownloadsFailedBanner: View {
    let failedCount: Int
    let onShowFailed: () -> Void
    let onRetryFailed: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(MAYNTheme.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text(DownloadsPagePresentation.failedBannerTitle(failedCount: failedCount))
                    .font(.callout.weight(.semibold))
                Text("Some videos could not be downloaded. Review failed items or retry them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            MAYNButton("Show Failed", role: .secondary, action: onShowFailed)
            MAYNButton("Retry Failed", role: .secondary, action: onRetryFailed)
        }
        .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
        .padding(.vertical, MAYNControlMetrics.rowVerticalPadding)
        .background(MAYNTheme.danger.opacity(0.08))
    }
}

struct DownloadsMetricsBar: View {
    let metrics: DownloadsPageMetrics

    var body: some View {
        HStack(spacing: 10) {
            DownloadsStatCell(title: "Total videos", value: metrics.totalVideos, dotColor: .neutral)
            DownloadsStatCell(title: "Completed", value: metrics.completed, dotColor: .success)
            DownloadsStatCell(title: "Active", value: metrics.activeCount, dotColor: .progress)
            DownloadsStatCell(title: "Paused", value: metrics.pausedCount, dotColor: .warning)
            DownloadsStatCell(title: "Failed", value: metrics.failedCount, dotColor: .danger)
        }
    }
}

private struct DownloadsStatCell: View {
    let title: String
    let value: Int
    let dotColor: DownloadsStatusDotColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(dotFill)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text("\(value)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, MAYNControlMetrics.rowControlSpacing)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MAYNTheme.window.opacity(0.62), in: RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }

    private var dotFill: Color {
        switch dotColor {
        case .neutral: Color.secondary.opacity(0.55)
        case .success: MAYNTheme.success
        case .progress: MAYNTheme.progress
        case .warning: MAYNTheme.warning
        case .danger: MAYNTheme.danger
        }
    }
}

struct DownloadsSectionHeading: View {
    let title: String
    let subtitle: String
    @Binding var viewMode: DownloadsPageViewMode

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            FunctionSegmentedTabStrip(
                tabs: Array(DownloadsPageViewMode.allCases),
                selection: viewMode,
                fillsAvailableWidth: false,
                equalSegmentWidths: true,
                size: .control
            ) { next in
                viewMode = next
            }
        }
        .padding(.horizontal, MAYNControlMetrics.rowControlSpacing)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }
}
