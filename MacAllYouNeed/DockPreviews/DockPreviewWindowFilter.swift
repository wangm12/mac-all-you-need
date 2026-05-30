import Foundation

/// Filters window entries to only include those eligible for preview display.
enum DockPreviewWindowFilter {
    static func filter(_ entries: [DockPreviewWindowEntry]) -> [DockPreviewWindowEntry] {
        entries.filter { entry in
            // Include on-screen windows and minimized windows
            entry.isOnScreen || entry.isMinimized
        }
    }
}
