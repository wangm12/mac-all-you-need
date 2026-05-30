import Foundation

/// Persists `ReminderSettings` in the App Group UserDefaults so the main app and
/// (read-only) extensions share the same configuration.
public enum ReminderSettingsStore {
    static let key = "reminders.settings"

    public static func load(from defaults: UserDefaults = AppGroupSettings.defaults) -> ReminderSettings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(ReminderSettings.self, from: data)
        else { return .default }
        return decoded
    }

    public static func save(_ settings: ReminderSettings, to defaults: UserDefaults = AppGroupSettings.defaults) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
    }
}
