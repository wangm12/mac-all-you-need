import AppKit
import Foundation

/// Represents a single window in the Dock preview panel.
struct DockPreviewWindowEntry: Identifiable, Equatable {
    let id: CGWindowID
    let pid: pid_t
    let title: String
    let frame: CGRect            // Quartz coords (origin at bottom-left)
    /// Populated only for display-bound copies (visible LRU hydration); not stored in `DockPreviewWindowCache`.
    var thumbnail: NSImage?
    var thumbnailCapturedAt: Date? = nil
    var isMinimized: Bool
    var isOnScreen: Bool

    /// Off-screen window that is not minimized (DockDoor `isHidden`).
    var isHidden: Bool { !isOnScreen && !isMinimized }

    static func == (lhs: DockPreviewWindowEntry, rhs: DockPreviewWindowEntry) -> Bool {
        lhs.id == rhs.id && lhs.isMinimized == rhs.isMinimized && lhs.title == rhs.title
    }

    /// Keep capture timestamps when a refresh returns entries without metadata yet.
    func mergingCaptureMetadata(from previous: DockPreviewWindowEntry?) -> DockPreviewWindowEntry {
        guard thumbnailCapturedAt == nil, let previous, let capturedAt = previous.thumbnailCapturedAt else { return self }
        var copy = self
        copy.thumbnailCapturedAt = capturedAt
        return copy
    }
}
