import AppKit
import Foundation

/// Security-scoped bookmarks for dock folder stack previews (DockDoor `folderWidgetAuthorizedBookmarks` subset).
enum DockFolderWidgetBookmarkStore {
    private static let defaultsKey = "dock.folderWidget.authorizedBookmarks"

    static func saveBookmark(for folderPath: String, data: Data) {
        var map = loadMap()
        map[folderPath] = data.base64EncodedString()
        saveMap(map)
    }

    static func resolvedURL(for folderPath: String) -> URL? {
        guard let encoded = loadMap()[folderPath],
              let data = Data(base64Encoded: encoded)
        else { return nil }
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    static func canReadDirectory(at url: URL) -> Bool {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }
        do {
            _ = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            return true
        } catch {
            return false
        }
    }

    @MainActor
    static func requestAccess(to url: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Choose this folder to show its contents in the dock preview."
        panel.prompt = "Allow Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = url.deletingLastPathComponent()

        guard panel.runModal() == .OK, let selected = panel.url else { return nil }
        guard selected.standardizedFileURL == url.standardizedFileURL else { return nil }

        if let bookmark = try? selected.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            saveBookmark(for: url.path, data: bookmark)
        }
        return selected
    }

    static func accessibleURL(for url: URL) -> URL? {
        if let bookmarked = resolvedURL(for: url.path), canReadDirectory(at: bookmarked) {
            return bookmarked
        }
        if canReadDirectory(at: url) { return url }
        return nil
    }

    private static func loadMap() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    private static func saveMap(_ map: [String: String]) {
        UserDefaults.standard.set(map, forKey: defaultsKey)
    }
}
