import AppKit
import Core
import FinderSync
import Foundation

/// FinderSync toolbar button that surfaces the user's recent folders. Reads the
/// same plaintext `folder-history.sqlite` written by the main app via the shared
/// App Group container, then opens recent folders from a popup menu.
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
        // Observe the whole home tree so the toolbar item is available broadly.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: NSHomeDirectory())]
    }

    override var toolbarItemName: String { "Recent Folders" }
    override var toolbarItemToolTip: String { "Show recently visited folders" }
    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "folder.badge.clock", accessibilityDescription: "Recent Folders") ?? NSImage()
    }

    override func beginObservingDirectory(at url: URL) {}
    override func endObservingDirectory(at url: URL) {}

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .toolbarItemMenu, let store else { return nil }
        let rows = (try? store.list(limit: 15)) ?? []
        let menu = NSMenu(title: "Recent Folders")
        if rows.isEmpty {
            let empty = NSMenuItem(title: "No recent folders", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return menu
        }
        for row in rows {
            let item = NSMenuItem(title: row.displayName, action: #selector(openFolder(_:)), keyEquivalent: "")
            item.target = self
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
