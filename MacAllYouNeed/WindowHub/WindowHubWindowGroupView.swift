import SwiftUI

struct WindowHubWindowGroupView: View {
    let group: WindowHubWindowGroup
    let appName: String
    var isBrowser = false
    var showGroupHeader = false
    var isExpanded = false
    var selectedTargetID: WindowHubTargetID?
    let onToggleExpansion: () -> Void
    let onSelect: (WindowHubTarget) -> Void
    let onActivate: (WindowHubTarget) -> Void
    let onAction: (WindowHubDirectAction, WindowHubTarget) -> Void

    private var presentationRows: [WindowHubPresentationRow] {
        WindowHubMasonryPacker.presentationRows(
            group: group,
            showGroupHeader: showGroupHeader,
            isExpanded: isExpanded,
            isBrowser: isBrowser
        )
    }

    private var totalTabs: Int {
        let tabTargets = group.visibleTargets.filter { $0.kind == .tab }
        return tabTargets.count + group.hiddenTabCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(presentationRows.enumerated()), id: \.offset) { _, row in
                switch row {
                case .groupHeader:
                    groupHeader
                case .target(let target):
                    WindowHubTargetRowView(
                        target: target,
                        isSelected: selectedTargetID == target.id,
                        showsDomain: isBrowser,
                        onActivate: { onActivate(target) },
                        onSelect: { onSelect(target) },
                        onAction: { action in onAction(action, target) }
                    )
                case .showAll:
                    showAllRow
                }
            }
        }
    }

    private var groupHeader: some View {
        HStack(spacing: 0) {
            if group.isActive {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(MAYNTheme.progress)
                    .frame(width: 2)
                    .padding(.vertical, 4)
            }

            HStack(spacing: 6) {
                Text(group.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if group.isActive {
                    Text("Current")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MAYNTheme.progress)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(MAYNTheme.progress.opacity(0.12), in: Capsule())
                }
                if totalTabs > 0 {
                    Text("\(totalTabs) tab\(totalTabs == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, group.isActive ? 6 : 8)
            .padding(.trailing, 8)
        }
        .frame(height: 26)
    }

    private var showAllRow: some View {
        Button(action: onToggleExpansion) {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                Text(
                    isExpanded
                        ? "Collapse"
                        : "Show all \(totalTabs) tab\(totalTabs == 1 ? "" : "s") in this window"
                )
                .font(.system(size: 12))
                Spacer(minLength: 6)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
