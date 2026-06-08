import AppKit
import Foundation

/// Application bundle discovery including custom scan directories (DockDoor `AppPickerSheet` subset).
enum DockAppDiscovery {
    static func defaultApplicationDirectories() -> [String] {
        [
            "/Applications",
            "/System/Applications",
            "/System/Cryptexes/App/System/Applications",
        ]
    }

    static func allApplicationDirectories(customDirectories: [String]) -> [String] {
        var paths = defaultApplicationDirectories()
        for dir in customDirectories where !paths.contains(dir) {
            paths.append(dir)
        }
        return paths
    }

    /// Bundle IDs found under configured application directories (best-effort).
    static func bundleIdentifiersInCustomDirectories(_ customDirectories: [String]) -> Set<String> {
        guard !customDirectories.isEmpty else { return [] }
        var ids = Set<String>()
        let manager = FileManager.default
        for root in customDirectories {
            guard let enumerator = manager.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator {
                guard url.pathExtension == "app",
                      let bundle = Bundle(url: url),
                      let id = bundle.bundleIdentifier
                else { continue }
                ids.insert(id)
                enumerator.skipDescendants()
            }
        }
        return ids
    }
}
