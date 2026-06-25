import Core
import Foundation

struct WindowHubRecentEntry: Codable, Equatable, Sendable {
    let targetID: WindowHubTargetID
    let breadcrumb: String
    let visitedAt: Date
}

enum WindowHubSnapshotStore {
    private static let recentKey = "windowHub.recentTargets"
    private static let maxRecent = 8

    static func loadRecent(from defaults: UserDefaults = AppGroupSettings.defaults) -> [WindowHubRecentEntry] {
        guard let data = defaults.data(forKey: recentKey),
              let decoded = try? JSONDecoder().decode([WindowHubRecentEntry].self, from: data)
        else { return [] }
        return decoded
    }

    static func recordVisit(_ target: WindowHubTarget, to defaults: UserDefaults = AppGroupSettings.defaults) {
        var recent = loadRecent(from: defaults).filter { $0.targetID != target.id }
        recent.insert(
            WindowHubRecentEntry(targetID: target.id, breadcrumb: target.breadcrumb, visitedAt: Date()),
            at: 0
        )
        if recent.count > maxRecent {
            recent = Array(recent.prefix(maxRecent))
        }
        if let data = try? JSONEncoder().encode(recent) {
            defaults.set(data, forKey: recentKey)
        }
    }
}
