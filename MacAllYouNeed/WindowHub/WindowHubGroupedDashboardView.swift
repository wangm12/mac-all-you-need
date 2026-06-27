import SwiftUI

struct WindowHubGroupedDashboardView: View {
    @Bindable var coordinator: WindowHubCoordinator

    var body: some View {
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
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(coordinator.snapshot.sections) { section in
                        WindowHubGroupedSectionView(
                            section: section,
                            selectedTargetID: coordinator.selectedTargetID,
                            tabsPerWindow: coordinator.settings.resolvedTabsPerWindow,
                            isLoading: coordinator.isLoading(pid: section.pid),
                            onSelect: { coordinator.selectTarget($0) },
                            onActivate: { target in
                                Task { await coordinator.activate(target: target) }
                            },
                            onAction: { action, target in
                                coordinator.requestDirectAction(action, target: target)
                            }
                        )
                    }
                }
                .padding(.vertical, 6)
                .opacity(coordinator.isIndexing ? 0.72 : 1)
            }
        }
    }
}

private struct WindowHubGroupedSectionView: View {
    let section: WindowHubAppSection
    let selectedTargetID: WindowHubTargetID?
    var tabsPerWindow = 10
    var isLoading = false
    let onSelect: (WindowHubTarget) -> Void
    let onActivate: (WindowHubTarget) -> Void
    let onAction: (WindowHubDirectAction, WindowHubTarget) -> Void

    private var windowCount: Int { section.windowGroups.count }
    private var tabCount: Int { WindowHubSectionMetrics.tabCount(in: section) }

    private var meta: String {
        if section.isBackgroundOnly { return "No windows" }
        let windows = "\(windowCount) window\(windowCount == 1 ? "" : "s")"
        return "\(windows) · \(tabCount) tab\(tabCount == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 0) {
                ForEach(section.windowGroups, id: \.id) { group in
                    WindowHubWindowGroupView(
                        group: group,
                        appName: section.appName,
                        tabsPerWindow: tabsPerWindow,
                        selectedTargetID: selectedTargetID,
                        onSelect: onSelect,
                        onActivate: onActivate,
                        onAction: onAction
                    )
                }
            }
            .padding(.leading, 12)
            Divider().overlay(MAYNTheme.hairline)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            WindowHubAppIcon(pid: section.pid)
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 14, height: 14)
            }
            Text(section.appName)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(meta)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
    }
}
