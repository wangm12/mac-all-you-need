import AppKit
import Foundation

/// Fast window list assembly for the global switcher (reads warm cache first).
@MainActor
enum DockSwitcherWindowCollector {
    static func collectCached(
        cache: DockPreviewWindowCache,
        hub: DockHubSettings
    ) -> [DockPreviewWindowEntry] {
        let previewSettings = previewSettings(from: hub)
        let apps = DockWindowDiscovery.runningRegularApplications()
        let appByPID = Dictionary(uniqueKeysWithValues: apps.map { ($0.processIdentifier, $0) })
        var collected: [DockPreviewWindowEntry] = []

        for app in apps {
            let windows = windowsForSwitcher(
                cache.readCached(pid: app.processIdentifier),
                app: app,
                hub: hub,
                previewSettings: previewSettings
            )
            collected.append(contentsOf: windows)
        }

        if hub.switcher.limitToFrontmostApp,
           let front = NSWorkspace.shared.frontmostApplication
        {
            collected = collected.filter { $0.pid == front.processIdentifier }
        }

        return sort(collected, order: hub.switcher.sortOrder, apps: appByPID)
    }

    static func refreshParallel(
        cache: DockPreviewWindowCache,
        enumerator: any WindowEnumerating,
        hub: DockHubSettings
    ) async -> [DockPreviewWindowEntry] {
        let previewSettings = previewSettings(from: hub)
        let apps = DockWindowDiscovery.runningRegularApplications()
        let appByPID = Dictionary(uniqueKeysWithValues: apps.map { ($0.processIdentifier, $0) })

        let eligible = apps.filter { app in
            !DockPreviewWindowFilter.isAppFiltered(
                bundleIdentifier: app.bundleIdentifier,
                appName: app.localizedName ?? "",
                filters: hub.filters
            )
        }

        var collected: [DockPreviewWindowEntry] = []
        await withTaskGroup(of: (pid_t, [DockPreviewWindowEntry]).self) { group in
            for app in eligible {
                let pid = app.processIdentifier
                group.addTask {
                    let entries = await enumerator.windows(
                        for: pid,
                        settings: previewSettings,
                        bundleIdentifier: app.bundleIdentifier
                    )
                    return (pid, entries)
                }
            }
            for await (pid, entries) in group {
                _ = cache.update(entries: entries, for: pid)
                guard let app = appByPID[pid] else { continue }
                let filtered = windowsForSwitcher(
                    entries,
                    app: app,
                    hub: hub,
                    previewSettings: previewSettings
                )
                collected.append(contentsOf: filtered)
            }
        }

        if hub.switcher.limitToFrontmostApp,
           let front = NSWorkspace.shared.frontmostApplication
        {
            collected = collected.filter { $0.pid == front.processIdentifier }
        }

        return sort(collected, order: hub.switcher.sortOrder, apps: appByPID)
    }

    private static func previewSettings(from hub: DockHubSettings) -> DockPreviewSettings {
        var settings = hub.previews
        settings.currentSpaceOnly = hub.switcher.currentSpaceOnly
        settings.currentMonitorOnly = hub.switcher.currentMonitorOnly
        settings.includeHiddenMinimized = hub.switcher.includeHiddenWindows
        settings.showWindowlessApps = hub.switcher.showWindowlessApps
        settings.useBroadWindowDiscovery = true
        return settings
    }

    private static func windowsForSwitcher(
        _ entries: [DockPreviewWindowEntry],
        app: NSRunningApplication,
        hub: DockHubSettings,
        previewSettings: DockPreviewSettings
    ) -> [DockPreviewWindowEntry] {
        if DockPreviewWindowFilter.isAppFiltered(
            bundleIdentifier: app.bundleIdentifier,
            appName: app.localizedName ?? "",
            filters: hub.filters
        ) {
            return []
        }

        var windows = DockPreviewWindowFilter.filterWindowTitles(entries, filters: hub.filters)
        windows = DockPreviewWindowFilter.filter(windows, settings: previewSettings)
        windows = DockPreviewWindowFilter.filterBySpace(windows, settings: previewSettings)

        windows = DockPreviewWindowFilter.filterByMonitor(
            windows,
            mouseLocation: NSEvent.mouseLocation,
            settings: previewSettings
        )

        if !hub.switcher.includeHiddenWindows {
            windows = windows.filter { !$0.isHidden && !$0.isMinimized }
        }

        return windows.filter { !$0.title.isEmpty || hub.switcher.showWindowlessApps }
    }

    private static func sort(
        _ entries: [DockPreviewWindowEntry],
        order: DockSortOrder,
        apps: [pid_t: NSRunningApplication]
    ) -> [DockPreviewWindowEntry] {
        switch order {
        case .recentlyUsed:
            return entries.sorted { lhs, rhs in
                let lb = apps[lhs.pid]?.bundleIdentifier
                let rb = apps[rhs.pid]?.bundleIdentifier
                let ld = DockPreviewWindowOrderStore.lastAccessed(bundleIdentifier: lb, windowTitle: lhs.title) ?? .distantPast
                let rd = DockPreviewWindowOrderStore.lastAccessed(bundleIdentifier: rb, windowTitle: rhs.title) ?? .distantPast
                if ld != rd { return ld > rd }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        case .creationOrder:
            return entries.sorted { $0.id < $1.id }
        case .alphabeticalByTitle:
            return entries.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .alphabeticalByAppName:
            return entries.sorted { lhs, rhs in
                let la = apps[lhs.pid]?.localizedName ?? ""
                let ra = apps[rhs.pid]?.localizedName ?? ""
                let appCompare = la.localizedCaseInsensitiveCompare(ra)
                if appCompare != .orderedSame { return appCompare == .orderedAscending }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }

}
