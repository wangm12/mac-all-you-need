import Core
import Foundation

enum DockPreviewSettingsStore {
    private static let prefix = "dockPreviews."

    static func load(from defaults: UserDefaults = AppGroupSettings.defaults) -> DockPreviewSettings {
        guard let data = defaults.data(forKey: key("settings")),
              let decoded = try? JSONDecoder().decode(DockPreviewSettings.self, from: data)
        else {
            return migrateLegacyKeys(from: defaults) ?? .default
        }
        return decoded
    }

    static func save(_ settings: DockPreviewSettings, to defaults: UserDefaults = AppGroupSettings.defaults) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key("settings"))
        NotificationCenter.default.post(name: .dockPreviewSettingsDidChange, object: nil)
    }

    private static func key(_ suffix: String) -> String { prefix + suffix }

    private static func migrateLegacyKeys(from defaults: UserDefaults) -> DockPreviewSettings? {
        var settings = DockPreviewSettings.default
        var migrated = false
        if defaults.object(forKey: "dockPreviews.showThumbnails") != nil {
            settings.showThumbnails = defaults.bool(forKey: "dockPreviews.showThumbnails")
            migrated = true
        }
        if defaults.object(forKey: "dockPreviews.hoverDelayMS") != nil {
            settings.hoverDelayMS = defaults.integer(forKey: "dockPreviews.hoverDelayMS")
            migrated = true
        }
        if migrated {
            save(settings, to: defaults)
        }
        return migrated ? settings : nil
    }
}

extension Notification.Name {
    static let dockPreviewSettingsDidChange = Notification.Name("dockPreviewSettingsDidChange")
}
