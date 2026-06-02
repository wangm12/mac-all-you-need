import Foundation

/// Maps dock app bundle IDs to embedded widget content (DockDoor widget routing subset).
enum DockPreviewEmbedRouting {
    private static let mediaBundleIDs: Set<String> = [
        "com.apple.Music",
        "com.apple.iTunes",
        "com.spotify.client",
    ]

    private static let calendarBundleIDs: Set<String> = [
        "com.apple.iCal",
        "com.apple.calendar",
        "com.apple.Calendar",
    ]

    static func embeddedContent(
        bundleIdentifier: String?,
        appName: String?,
        widgets: DockWidgetSettings,
        filters: DockFilterSettings
    ) -> DockEmbeddedContent {
        guard let bundleIdentifier else { return .none }
        if isWidgetFiltered(bundleIdentifier: bundleIdentifier, appName: appName, filters: filters) {
            return .none
        }
        if widgets.enableMediaWidget, matchesMedia(bundleIdentifier: bundleIdentifier, widgets: widgets) {
            return .media
        }
        if widgets.enableCalendarWidget, calendarBundleIDs.contains(bundleIdentifier) {
            return .calendar
        }
        return .none
    }

    private static func isWidgetFiltered(
        bundleIdentifier: String,
        appName: String?,
        filters: DockFilterSettings
    ) -> Bool {
        guard !filters.widgetAppFilters.isEmpty else { return false }
        let name = appName?.lowercased() ?? ""
        let bundle = bundleIdentifier.lowercased()
        return filters.widgetAppFilters.contains { filter in
            let f = filter.lowercased()
            return name.contains(f) || bundle.contains(f)
        }
    }

    private static func matchesMedia(bundleIdentifier: String, widgets: DockWidgetSettings) -> Bool {
        switch widgets.mediaDetectionMode {
        case .universal:
            return mediaBundleIDs.contains(bundleIdentifier)
        case .appleScriptOnly:
            return bundleIdentifier == "com.apple.Music"
                || bundleIdentifier == "com.apple.iTunes"
                || bundleIdentifier == "com.spotify.client"
        }
    }
}
