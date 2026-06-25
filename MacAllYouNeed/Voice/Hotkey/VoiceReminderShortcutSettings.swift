import Core
import Foundation
import Platform

struct VoiceReminderShortcutSettings: Codable, Equatable {
    var shortcut: HotkeyDescriptor

    static let `default` = VoiceReminderShortcutSettings(shortcut: .defaultVoiceReminder)
}

enum VoiceReminderShortcutSettingsStore {
    private static let key = "voice.reminder.shortcut.settings.v1"

    static func load(from defaults: UserDefaults = AppGroupSettings.defaults) -> VoiceReminderShortcutSettings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(VoiceReminderShortcutSettings.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    static func save(_ settings: VoiceReminderShortcutSettings, to defaults: UserDefaults = AppGroupSettings.defaults) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
