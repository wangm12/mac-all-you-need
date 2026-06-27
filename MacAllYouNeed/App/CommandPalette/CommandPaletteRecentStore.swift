import Core
import Foundation

enum CommandPaletteRecentStore {
    static let storageKey = "commandPalette.recentActionIDs"
    static let maxCount = 5

    static func load(from defaults: UserDefaults = AppGroupSettings.defaults) -> [String] {
        defaults.stringArray(forKey: storageKey) ?? []
    }

    static func record(_ actionID: String, in defaults: UserDefaults = AppGroupSettings.defaults) {
        var recent = load(from: defaults).filter { $0 != actionID }
        recent.insert(actionID, at: 0)
        if recent.count > maxCount {
            recent = Array(recent.prefix(maxCount))
        }
        defaults.set(recent, forKey: storageKey)
    }
}
