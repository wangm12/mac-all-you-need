import AppKit
import Foundation

/// Represents a single window in the Dock preview panel.
struct DockPreviewWindowEntry: Identifiable, Equatable {
    let id: CGWindowID
    let pid: pid_t
    let title: String
    let frame: CGRect            // Quartz coords (origin at bottom-left)
    var thumbnail: NSImage?      // nil = loading or Screen Recording denied
    var isMinimized: Bool
    var isOnScreen: Bool

    static func == (lhs: DockPreviewWindowEntry, rhs: DockPreviewWindowEntry) -> Bool {
        lhs.id == rhs.id && lhs.isMinimized == rhs.isMinimized && lhs.title == rhs.title
    }
}
