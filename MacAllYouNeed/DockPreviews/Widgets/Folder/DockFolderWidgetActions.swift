import AppKit
import Core
import Foundation

/// Cross-feature actions from the dock folder widget.
@MainActor
enum DockFolderWidgetActions {
    static func openInFinder(url: URL) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }

    static func browseInApp(url: URL) {
        NotificationCenter.default.post(
            name: .browseFolderRequested,
            object: nil,
            userInfo: ["url": url]
        )
    }

    static func addToFolderHistory(path: String) {
        guard let store = FolderHistoryStoreLocator.shared() else { return }
        try? store.upsert(path: path)
    }
}
