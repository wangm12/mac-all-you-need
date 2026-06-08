import AppKit
import Foundation
import Platform

enum DockPreviewWindowFilter {
    static func isAppFiltered(
        bundleIdentifier: String?,
        appName: String,
        filters: DockFilterSettings
    ) -> Bool {
        let list = filters.appNameFilters
        guard !list.isEmpty else { return false }
        if let bundleIdentifier, list.contains(bundleIdentifier) { return true }
        return list.contains { $0.caseInsensitiveCompare(appName) == .orderedSame }
    }

    static func filterWindowTitles(
        _ entries: [DockPreviewWindowEntry],
        filters: DockFilterSettings
    ) -> [DockPreviewWindowEntry] {
        let titleFilters = filters.windowTitleFilters
        guard !titleFilters.isEmpty else { return entries }
        return entries.filter { entry in
            let title = entry.title.lowercased()
            return !titleFilters.contains { title.contains($0.lowercased()) }
        }
    }

    static func applyHubFilters(
        _ entries: [DockPreviewWindowEntry],
        hub: DockHubSettings,
        bundleIdentifier: String?,
        appName: String
    ) -> [DockPreviewWindowEntry] {
        guard !isAppFiltered(bundleIdentifier: bundleIdentifier, appName: appName, filters: hub.filters) else {
            return []
        }
        return filterWindowTitles(entries, filters: hub.filters)
    }

    static func filter(_ entries: [DockPreviewWindowEntry], settings: DockPreviewSettings) -> [DockPreviewWindowEntry] {
        entries.filter { entry in
            if entry.isOnScreen { return true }
            if settings.includeHiddenMinimized {
                return entry.isMinimized || entry.isHidden
            }
            return false
        }
    }

    static func filterBySpace(_ entries: [DockPreviewWindowEntry], settings: DockPreviewSettings) -> [DockPreviewWindowEntry] {
        guard settings.currentSpaceOnly else { return entries }
        let activeSpaces = DockPreviewSpaceQuery.activeSpaceIDs()
        guard !activeSpaces.isEmpty else { return entries }
        return entries.filter { entry in
            if entry.isMinimized || !entry.isOnScreen {
                return settings.includeHiddenMinimized
            }
            let spaces = DockPreviewSpaceQuery.spaceIDs(for: entry.id)
            if spaces.isEmpty { return true }
            return !Set(spaces).isDisjoint(with: activeSpaces)
        }
    }

    static func filterByMonitor(
        _ entries: [DockPreviewWindowEntry],
        dockIconRect: CGRect,
        settings: DockPreviewSettings
    ) -> [DockPreviewWindowEntry] {
        filterByMonitor(
            entries,
            mouseLocation: CGPoint(x: dockIconRect.midX, y: dockIconRect.midY),
            settings: settings,
            locationIsQuartz: true
        )
    }

    static func filterByMonitor(
        _ entries: [DockPreviewWindowEntry],
        mouseLocation: CGPoint,
        settings: DockPreviewSettings,
        locationIsQuartz: Bool = false
    ) -> [DockPreviewWindowEntry] {
        guard settings.currentMonitorOnly else { return entries }
        guard let screen = screenContaining(point: mouseLocation, locationIsQuartz: locationIsQuartz) else {
            return entries
        }
        return entries.filter { entry in
            if settings.includeHiddenMinimized, entry.isMinimized || entry.isHidden {
                return true
            }
            return screen.frame.intersects(quartzRectToScreenFrame(entry.frame))
        }
    }

    private static func screenContaining(point: CGPoint, locationIsQuartz: Bool) -> NSScreen? {
        if locationIsQuartz {
            return NSScreen.screenFromQuartzPoint(point)
        }
        return NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    private static func quartzRectToScreenFrame(_ quartz: CGRect) -> CGRect {
        let origin = WindowScreenDetector.appKitPoint(fromCG: quartz.origin)
        return CGRect(origin: origin, size: quartz.size)
    }
}
