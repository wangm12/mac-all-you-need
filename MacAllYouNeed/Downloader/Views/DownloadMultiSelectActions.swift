import AppKit
import Core
import Foundation

// MARK: - Selection controller

/// Pure logic for multi-select tap handling and keyboard selection commands.
/// All methods are static and mutation-based; no view dependencies.
enum DownloadsListSelectionController {

    /// Apply a tap with optional modifier keys to the selection state.
    static func applyTap(
        id: String,
        visibleRows: [DownloadRecord],
        selectedIDs: inout Set<String>,
        anchorID: inout String?,
        modifiers: NSEvent.ModifierFlags
    ) {
        let isCommand = modifiers.contains(.command)
        let isShift = modifiers.contains(.shift)

        if isCommand {
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
            } else {
                selectedIDs.insert(id)
                anchorID = id
            }
        } else if isShift, let anchor = anchorID {
            let ids = visibleRows.map(\.id.rawValue)
            if let start = ids.firstIndex(of: anchor),
               let end = ids.firstIndex(of: id)
            {
                let lo = min(start, end)
                let hi = max(start, end)
                selectedIDs = Set(ids[lo ... hi])
            }
        } else {
            if selectedIDs == [id] {
                selectedIDs = []
                anchorID = nil
            } else {
                selectedIDs = [id]
                anchorID = id
            }
        }
    }

    /// Select all visible rows (⌘A).
    static func applySelectAll(
        visibleRows: [DownloadRecord],
        selectedIDs: inout Set<String>,
        anchorID: inout String?
    ) {
        selectedIDs = Set(visibleRows.map(\.id.rawValue))
        anchorID = visibleRows.first?.id.rawValue
    }

    /// Clear selection on Escape.
    /// Returns `true` if the event was consumed (selection was non-empty), `false` if it was a no-op.
    @discardableResult
    static func applyEscape(
        selectedIDs: inout Set<String>,
        anchorID: inout String?
    ) -> Bool {
        guard !selectedIDs.isEmpty else { return false }
        selectedIDs = []
        anchorID = nil
        return true
    }
}
