import Foundation

/// Internal drag payload encoded as a String so we don't have to register a
/// custom UTI in Info.plist (which `UTType(exportedAs:)` expects). The
/// "dockitem://" marker prefix lets tabs filter out unrelated text drags.
enum DockItemDrag {
    static let prefix = "dockitem://"

    /// Encode `item.id` (preview is intentionally not included so external
    /// text drops onto Notes/etc don't see our marker; that path will use
    /// the inner card's content draggable when we re-add it).
    static func encode(recordID: String) -> String {
        prefix + recordID
    }

    static func decode(_ raw: String) -> String? {
        guard raw.hasPrefix(prefix) else { return nil }
        let id = String(raw.dropFirst(prefix.count))
        return id.isEmpty ? nil : id
    }
}

/// Drag payload for reordering user-created pinboard tabs. Uses the same
/// String + marker-prefix scheme as `DockItemDrag` so the tab's drop handler
/// can dispatch on prefix and not confuse a tab-reorder drag with an item-pin
/// drag.
enum DockTabDrag {
    static let prefix = "pinboardtab://"

    static func encode(boardID: String) -> String {
        prefix + boardID
    }

    static func decode(_ raw: String) -> String? {
        guard raw.hasPrefix(prefix) else { return nil }
        let id = String(raw.dropFirst(prefix.count))
        return id.isEmpty ? nil : id
    }
}

/// Sent by `CardContextMenu` when the user picks "Paste to <App>" or
/// "Paste as Plain Text". `DockWindowController` observes it and routes
/// through `triggerPaste(at:modifiers:)` so the dock dismiss + focus-restore
/// + delay logic in `DockPasteCoordinator` is reused.
struct DockPasteIntent {
    let itemID: String
    let plainText: Bool
}

extension Notification.Name {
    static let dockPasteRequested = Notification.Name("dockPasteRequested")
    /// Posted by views inside the dock when an action (e.g. double-click
    /// copy) wants to dismiss the panel without going through the responder
    /// chain. The DockWindowController observes during its visible window.
    static let dockHideRequested = Notification.Name("dockHideRequested")
}
