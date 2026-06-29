import SwiftUI

struct WindowHubMasonryDashboardView: View {
    @Bindable var coordinator: WindowHubCoordinator
    @State private var expandedGroupIDs: Set<String> = []
    @State private var packedColumns: [[WindowHubAppSection]] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let columns = packedColumns
            ScrollView {
                if coordinator.isIndexing && coordinator.snapshot.sections.isEmpty {
                    ProgressView("Indexing windows…")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else if visibleSections.isEmpty, !coordinator.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    emptySearchState
                } else if visibleSections.isEmpty {
                    ContentUnavailableView(
                        "No windows found",
                        systemImage: "macwindow",
                        description: Text("Open an app window or grant Accessibility permission.")
                    )
                } else {
                    masonry(columns: columns)
                        .opacity(coordinator.isIndexing ? 0.72 : 1)
                }
            }
            .onAppear {
                repack(width: proxy.size.width)
            }
            .onChange(of: proxy.size.width) { _, width in
                repack(width: width)
            }
            .onChange(of: coordinator.snapshot.sections.map(\.id)) { _, _ in
                repack(width: proxy.size.width)
            }
            .onChange(of: coordinator.searchQuery) { _, _ in
                repack(width: proxy.size.width)
            }
            .onChange(of: expandedGroupIDs) { _, _ in
                repack(width: proxy.size.width)
            }
        }
    }

    private var visibleSections: [WindowHubAppSection] {
        coordinator.filteredSections
    }

    private var emptySearchState: some View {
        VStack(spacing: 8) {
            Text("No matching windows or tabs")
                .font(.system(size: 14, weight: .semibold))
            Text("Try an app name, window title, tab title, or domain")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private func masonry(columns: [[WindowHubAppSection]]) -> some View {
        HStack(alignment: .top, spacing: WindowHubMasonryPacker.columnGap) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                LazyVStack(alignment: .leading, spacing: WindowHubMasonryPacker.cardGap) {
                    ForEach(column) { section in
                        WindowHubAppCardView(
                            section: section,
                            currentTargetID: coordinator.snapshot.currentTargetID,
                            selectedTargetID: coordinator.selectedTargetID,
                            expandedGroupIDs: expandedGroupIDs,
                            isLoading: coordinator.isLoading(pid: section.pid),
                            isPartial: coordinator.isSectionPartial(section),
                            onToggleExpansion: toggleExpansion(for:),
                            onSelect: { coordinator.selectTarget($0) },
                            onActivate: { target in
                                Task { await coordinator.activate(target: target) }
                            },
                            onAction: { action, target in
                                coordinator.requestDirectAction(action, target: target)
                            }
                        )
                        .transition(
                            .opacity.combined(with: .offset(y: reduceMotion ? 0 : 4))
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .padding(WindowHubMasonryPacker.contentPadding)
        .animation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion), value: columns.map { $0.map(\.id) })
    }

    private func repack(width: CGFloat) {
        let count = WindowHubMasonryPacker.columnCount(for: width)
        let sorted = WindowHubMasonryPacker.prioritySorted(
            visibleSections,
            frontPID: coordinator.frontmostPID,
            currentTargetID: coordinator.snapshot.currentTargetID,
            recentTargetIDs: coordinator.recentEntries.map(\.targetID)
        )
        let isBrowser = WindowHubSectionMetrics.isBrowserSection
        packedColumns = WindowHubMasonryPacker.pack(
            sections: sorted,
            columnCount: count,
            expandedGroupIDs: expandedGroupIDs,
            isBrowser: isBrowser
        )
        let navigable = WindowHubMasonryPacker.flatTargets(
            in: packedColumns,
            expandedGroupIDs: expandedGroupIDs,
            isBrowser: isBrowser
        )
        let columnTargets = packedColumns.map { column in
            WindowHubMasonryPacker.flatTargets(
                in: [column],
                expandedGroupIDs: expandedGroupIDs,
                isBrowser: isBrowser
            )
        }
        coordinator.updateMasonryNavigableTargets(navigable, columnTargets: columnTargets)
    }

    private func toggleExpansion(for groupID: String) {
        withAnimation(MAYNMotion.fastAnimation(reduceMotion: reduceMotion)) {
            if expandedGroupIDs.contains(groupID) {
                expandedGroupIDs.remove(groupID)
            } else {
                expandedGroupIDs.insert(groupID)
            }
        }
    }
}
