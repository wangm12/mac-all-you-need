import SwiftUI

struct WindowHubMasonryDashboardView: View {
    @Bindable var coordinator: WindowHubCoordinator

    /// Target width for one masonry column; column count flexes with the panel size.
    private static let targetColumnWidth: CGFloat = 384
    private static let maxColumns = 4

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                if coordinator.isIndexing && coordinator.snapshot.sections.isEmpty {
                    ProgressView("Indexing windows…")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else if coordinator.snapshot.sections.isEmpty {
                    ContentUnavailableView(
                        "No windows found",
                        systemImage: "macwindow",
                        description: Text("Open an app window or grant Accessibility permission.")
                    )
                } else {
                    masonry(columnCount: columnCount(for: proxy.size.width))
                        .opacity(coordinator.isIndexing ? 0.72 : 1)
                }
            }
        }
    }

    private func columnCount(for width: CGFloat) -> Int {
        let usable = max(0, width - 18)
        let count = Int((usable / Self.targetColumnWidth).rounded(.down))
        return min(Self.maxColumns, max(1, count))
    }

    private func masonry(columnCount: Int) -> some View {
        let columns = Self.distribute(sections: coordinator.snapshot.sections, columnCount: columnCount)
        return HStack(alignment: .top, spacing: 9) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                LazyVStack(alignment: .leading, spacing: 9) {
                    ForEach(column) { section in
                        WindowHubAppSectionView(
                            section: section,
                            tabsPerWindow: coordinator.settings.resolvedTabsPerWindow,
                            isLoading: coordinator.isLoading(pid: section.pid)
                        ) { target in
                            Task { await coordinator.activate(target: target) }
                        } onAction: { action, target in
                            coordinator.requestDirectAction(action, target: target)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .padding(9)
    }

    /// Greedy masonry: append each section to the currently shortest column,
    /// using an estimated row count as the height proxy (mirrors the design).
    static func distribute(sections: [WindowHubAppSection], columnCount: Int) -> [[WindowHubAppSection]] {
        guard columnCount > 0 else { return [sections] }
        var columns = Array(repeating: [WindowHubAppSection](), count: columnCount)
        var heights = Array(repeating: 0, count: columnCount)
        for section in sections {
            let index = heights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            columns[index].append(section)
            heights[index] += estimatedHeight(of: section)
        }
        return columns
    }

    private static func estimatedHeight(of section: WindowHubAppSection) -> Int {
        // Section header ≈ 2 row-units.
        var units = 2
        for group in section.windowGroups {
            let tabCount = group.visibleTargets.filter { $0.kind == .tab }.count
            // primary line (1) + capped "other" tab rows (≈ default collapse cap)
            let others = max(0, tabCount - 1)
            let shownOthers = min(others, 9)
            units += 1 + shownOthers + (others > shownOthers ? 1 : 0)
        }
        return units
    }
}
