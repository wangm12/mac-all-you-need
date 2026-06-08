import AppKit
import Core
import FinderSync
import Foundation

/// FinderSync toolbar button: read-only recent-folders menu (no search).
/// Capture lives in the main app; this extension only reads the shared store and opens paths.
@objc(FinderSyncExtension)
final class FinderSyncExtension: FIFinderSync {
    private var store: FolderHistoryStore?

    override init() {
        super.init()
        if let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.macallyouneed.shared")?
            .appendingPathComponent("databases/folder-history.sqlite")
        {
            store = try? FolderHistoryStore(url: url)
        }
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: NSHomeDirectory())]
    }

    override var toolbarItemName: String { "Recent Folders" }
    override var toolbarItemToolTip: String { "Recently visited folders" }
    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "folder.badge.clock", accessibilityDescription: "Recent Folders") ?? NSImage()
    }

    override func beginObservingDirectory(at url: URL) {}
    override func endObservingDirectory(at url: URL) {}

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .toolbarItemMenu, let store else { return nil }
        return Self.recentFoldersMenu(store: store, openAction: #selector(openFolder(_:)), target: self)
    }

    /// Builds a plain recents menu (pinned first, no search field).
    static func recentFoldersMenu(
        store: FolderHistoryStore,
        openAction: Selector,
        target: AnyObject
    ) -> NSMenu {
        let menu = NSMenu(title: "Recent Folders")
        let rows = (try? store.list(limit: FolderHistoryDisplayLimits.quickPickCount)) ?? []
        let existing = rows.filter { FileManager.default.fileExists(atPath: $0.path) }
        if existing.isEmpty {
            let empty = NSMenuItem(title: "No recent folders", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return menu
        }
        for row in existing {
            let item = NSMenuItem(title: row.displayName, action: openAction, keyEquivalent: "")
            item.target = target
            item.toolTip = row.path
            item.representedObject = row.path
            menu.addItem(item)
        }
        return menu
    }

    @objc private func openFolder(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
