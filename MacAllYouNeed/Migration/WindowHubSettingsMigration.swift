import Core
import Foundation

/// One-shot settings migration for Window Hub defaults that changed after
/// launch. Keeps existing user choices intact after the migration has run.
enum WindowHubSettingsMigration {
    private static let doneKey = "windowHub.settingsMigration.v1.done"

    static func migrateIfNeeded(defaults: UserDefaults = AppGroupSettings.defaults) {
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }

        let current = WindowHubSettingsStore.load(from: defaults)
        guard current.browserTabDiscoveryEnabled == false else { return }

        var migrated = current
        migrated.browserTabDiscoveryEnabled = true
        WindowHubSettingsStore.save(migrated, to: defaults)
    }
}
