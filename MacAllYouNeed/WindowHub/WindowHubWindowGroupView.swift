import SwiftUI

struct WindowHubWindowGroupView: View {
    let group: WindowHubWindowGroup
    let appName: String
    var tabsPerWindow = 10
    var selectedTargetID: WindowHubTargetID?
    let onSelect: (WindowHubTarget) -> Void
    let onActivate: (WindowHubTarget) -> Void
    let onAction: (WindowHubDirectAction, WindowHubTarget) -> Void

    @State private var isExpanded = false

    private var tabTargets: [WindowHubTarget] {
        group.visibleTargets.filter { $0.kind == .tab }
    }

    private var isTabbed: Bool { !tabTargets.isEmpty }
    private var totalTabs: Int { tabTargets.count }

    /// Active targets first, then the rest — same row styling for every line.
    private var orderedTargets: [WindowHubTarget] {
        if isTabbed {
            let active = tabTargets.filter(\.isActive)
            let rest = tabTargets.filter { !$0.isActive }
            return active + rest
        }
        return group.visibleTargets
    }

    private var shownTargets: [WindowHubTarget] {
        isExpanded ? orderedTargets : Array(orderedTargets.prefix(tabsPerWindow))
    }

    private var hiddenCount: Int {
        max(0, orderedTargets.count - shownTargets.count)
    }

    private var canExpand: Bool { hiddenCount > 0 || (isExpanded && orderedTargets.count > tabsPerWindow) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(shownTargets, id: \.id) { target in
                WindowHubTargetRowView(
                    target: target,
                    isSelected: selectedTargetID == target.id,
                    onActivate: { onActivate(target) },
                    onSelect: { onSelect(target) },
                    onAction: { action in onAction(action, target) }
                )
            }

            if canExpand {
                expandRow
            }
        }
    }

    private var expandRow: some View {
        Button {
            withAnimation(MAYNMotion.fast) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                Text(isExpanded ? "Collapse" : "Show all \(totalTabs) tabs")
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
