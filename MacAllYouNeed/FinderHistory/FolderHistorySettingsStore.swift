import Core
import Foundation

/// User preferences for Finder Folder History (App Group `UserDefaults`).
struct FolderHistorySettings: Equatable, Codable {
    var isPaused: Bool
    var excludedPaths: [String]
    var retentionMax: Int

    static let `default` = FolderHistorySettings(
        isPaused: false,
        excludedPaths: [],
        retentionMax: 500
    )
}

enum FolderHistorySettingsStore {
    private static let key = "folderHistory.settings"

    static func load() -> FolderHistorySettings {
        guard let data = AppGroupSettings.defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(FolderHistorySettings.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    static func save(_ settings: FolderHistorySettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        AppGroupSettings.defaults.set(data, forKey: key)
    }
}
