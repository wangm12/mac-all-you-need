import Foundation

/// Maps dock app bundle IDs to embedded widget content (DockDoor widget routing subset).
enum DockPreviewEmbedRouting {
    private static let mediaBundleIDs: Set<String> = [
        "com.apple.Music",
        "com.apple.iTunes",
    ]

    private static let calendarBundleIDs: Set<String> = [
        "com.apple.iCal",
        "com.apple.calendar",
        "com.apple.Calendar",
    ]

    static func embeddedContent(
        bundleIdentifier: String?,
        widgets: DockWidgetSettings
    ) -> DockEmbeddedContent {
        guard let bundleIdentifier else { return .none }
        if widgets.enableMediaWidget, mediaBundleIDs.contains(bundleIdentifier) {
            return .media
        }
        if widgets.enableCalendarWidget, calendarBundleIDs.contains(bundleIdentifier) {
            return .calendar
        }
        return .none
    }
}
