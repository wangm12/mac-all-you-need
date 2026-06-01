import Core
import Foundation

/// Tracks window activation order for "Recently used" sort (DockDoor `WindowOrderPersistence` behavior).
enum DockPreviewWindowOrderStore {
    private static let storageKey = "dockPreviews.windowOrder"
    private static let maxEntries = 500

    struct Entry: Codable, Equatable {
        let bundleIdentifier: String
        let windowTitle: String
        var lastAccessed: Date

        var lookupKey: String { "\(bundleIdentifier)|\(windowTitle)" }
    }

    private static var memoryCache: [String: Entry]?

    static func recordActivation(bundleIdentifier: String?, windowTitle: String) {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return }
        let key = "\(bundleIdentifier)|\(windowTitle)"
        var entries = loadEntries()
        if var existing = entries[key] {
            existing.lastAccessed = Date()
            entries[key] = existing
        } else {
            entries[key] = Entry(
                bundleIdentifier: bundleIdentifier,
                windowTitle: windowTitle,
                lastAccessed: Date()
            )
        }
        persist(entries)
    }

    static func lastAccessed(bundleIdentifier: String?, windowTitle: String) -> Date? {
        guard let bundleIdentifier else { return nil }
        let key = "\(bundleIdentifier)|\(windowTitle)"
        return loadEntries()[key]?.lastAccessed
    }

    static func sort(
        _ entries: [DockPreviewWindowEntry],
        bundleIdentifier: String?,
        order: DockPreviewSortOrder
    ) -> [DockPreviewWindowEntry] {
        switch order {
        case .titleAscending:
            return entries.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .titleDescending:
            return entries.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .recentlyUsed:
            return entries.sorted { lhs, rhs in
                let lhsDate = lastAccessed(bundleIdentifier: bundleIdentifier, windowTitle: lhs.title) ?? .distantPast
                let rhsDate = lastAccessed(bundleIdentifier: bundleIdentifier, windowTitle: rhs.title) ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }

    private static func loadEntries() -> [String: Entry] {
        if let memoryCache { return memoryCache }
        guard let data = AppGroupSettings.defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data)
        else {
            memoryCache = [:]
            return [:]
        }
        let map = Dictionary(uniqueKeysWithValues: decoded.map { ($0.lookupKey, $0) })
        memoryCache = map
        return map
    }

    private static func persist(_ entries: [String: Entry]) {
        let sorted = entries.values.sorted { $0.lastAccessed > $1.lastAccessed }.prefix(maxEntries)
        memoryCache = Dictionary(uniqueKeysWithValues: sorted.map { ($0.lookupKey, $0) })
        if let data = try? JSONEncoder().encode(Array(sorted)) {
            AppGroupSettings.defaults.set(data, forKey: storageKey)
        }
    }
}
