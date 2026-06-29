import AppKit
import SwiftUI

enum WindowHubSectionMetrics {
    static func tabCount(in section: WindowHubAppSection) -> Int {
        section.windowGroups.reduce(0) { sum, group in
            sum + group.visibleTargets.filter { $0.kind == .tab }.count + group.hiddenTabCount
        }
    }

    static func isBrowserSection(_ section: WindowHubAppSection) -> Bool {
        section.windowGroups.contains { group in
            group.visibleTargets.contains { target in
                target.kind == .tab && target.capabilities.contains(.readDomain)
            }
        }
    }

    static func headerMeta(for section: WindowHubAppSection) -> String {
        if section.isBackgroundOnly { return "No windows" }
        let windowCount = section.windowGroups.count
        let windows = "\(windowCount) window\(windowCount == 1 ? "" : "s")"
        let tabCount = tabCount(in: section)
        if isBrowserSection(section), tabCount > 0 {
            return "\(windows) · \(tabCount) tab\(tabCount == 1 ? "" : "s")"
        }
        return windows
    }

    static func sectionContainsCurrentTarget(
        _ section: WindowHubAppSection,
        currentTargetID: WindowHubTargetID?
    ) -> Bool {
        guard let currentTargetID else { return false }
        return section.windowGroups.contains { group in
            group.isActive || group.visibleTargets.contains { $0.id == currentTargetID }
        }
    }
}

struct WindowHubAppCardView: View {
    let section: WindowHubAppSection
    let currentTargetID: WindowHubTargetID?
    let selectedTargetID: WindowHubTargetID?
    let expandedGroupIDs: Set<String>
    var isLoading = false
    var isPartial = false
    let onToggleExpansion: (String) -> Void
    let onSelect: (WindowHubTarget) -> Void
    let onActivate: (WindowHubTarget) -> Void
    let onAction: (WindowHubDirectAction, WindowHubTarget) -> Void

    private var isBrowser: Bool { WindowHubSectionMetrics.isBrowserSection(section) }
    private var isCurrentSection: Bool {
        WindowHubSectionMetrics.sectionContainsCurrentTarget(section, currentTargetID: currentTargetID)
    }

    var body: some View {
        HStack(spacing: 0) {
            if isCurrentSection {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(MAYNTheme.progress)
                    .frame(width: 3)
                    .padding(.vertical, 8)
            }

            VStack(alignment: .leading, spacing: 0) {
                header
                MAYNDivider()
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(section.windowGroups, id: \.id) { group in
                        WindowHubWindowGroupView(
                            group: group,
                            appName: section.appName,
                            isBrowser: isBrowser,
                            showGroupHeader: isBrowser && section.windowGroups.count > 1,
                            isExpanded: expandedGroupIDs.contains(group.id),
                            selectedTargetID: selectedTargetID,
                            onToggleExpansion: { onToggleExpansion(group.id) },
                            onSelect: onSelect,
                            onActivate: onActivate,
                            onAction: onAction
                        )
                    }
                }
                .padding(9)
            }
        }
        .background(MAYNTheme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
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
                .font(.system(size: 13.5, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 6)
            if isPartial {
                Text("Partial")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(WindowHubSectionMetrics.headerMeta(for: section))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
    }
}

/// Resolves the running app's Dock icon for the section header. Cached by pid.
struct WindowHubAppIcon: View {
    let pid: pid_t

    var body: some View {
        Group {
            if let image = WindowHubAppIconCache.icon(for: pid) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 18, height: 18)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

enum WindowHubAppIconCache {
    private static var cache: [pid_t: NSImage] = [:]

    @MainActor
    static func icon(for pid: pid_t) -> NSImage? {
        if let cached = cache[pid] { return cached }
        guard let icon = NSRunningApplication(processIdentifier: pid)?.icon else { return nil }
        cache[pid] = icon
        return icon
    }
}
