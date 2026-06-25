import AppKit
import SwiftUI

enum WindowHubSectionMetrics {
    static func tabCount(in section: WindowHubAppSection) -> Int {
        section.windowGroups.reduce(0) { sum, group in
            sum + group.visibleTargets.filter { $0.kind == .tab }.count + group.hiddenTabCount
        }
    }
}

struct WindowHubAppSectionView: View {
    let section: WindowHubAppSection
    var tabsPerWindow = 10
    var isLoading = false
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
            Divider()
                .overlay(MAYNTheme.subtleBorder)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(section.windowGroups, id: \.id) { group in
                    WindowHubWindowGroupView(
                        group: group,
                        appName: section.appName,
                        tabsPerWindow: tabsPerWindow,
                        onActivate: onActivate,
                        onAction: onAction
                    )
                }
            }
            .padding(7)
        }
        .background(MAYNTheme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 7) {
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
        .padding(.horizontal, 9)
        .frame(height: 32)
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
