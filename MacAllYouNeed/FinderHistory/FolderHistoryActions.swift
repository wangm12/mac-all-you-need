import AppKit
import Foundation

/// Routes folder-history selections to Finder.
enum FolderHistoryActions {
    /// Opens the folder in a new (or existing) Finder window.
    static func open(path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    /// Reveals the folder, selecting it in its parent Finder window.
    static func reveal(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
