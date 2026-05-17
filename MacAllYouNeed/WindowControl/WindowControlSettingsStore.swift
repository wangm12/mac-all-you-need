import Core
import Foundation

enum WindowControlSettingsStore {
    static let key = "windowControl.settings.v1"

    static func load(from defaults: UserDefaults = AppGroupSettings.defaults) -> WindowControlSettings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(WindowControlSettings.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    static func save(_ settings: WindowControlSettings, to defaults: UserDefaults = AppGroupSettings.defaults) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
        postSettingsChangedDarwin()
    }

    private static func postSettingsChangedDarwin() {
        let name = "com.macallyouneed.settings-changed" as CFString
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name),
            nil,
            nil,
            true
        )
    }
}
