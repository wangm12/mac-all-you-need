import Core
import Foundation

/// Single source of truth for the "migration ran already" flag.
/// Persists across upgrades via AppGroupSettings.
enum MigrationSentinel {
    static let key = "migratedToFeatureModel"

    static func hasMigrated(defaults: UserDefaults = AppGroupSettings.defaults) -> Bool {
        defaults.bool(forKey: key)
    }

    static func markMigrated(defaults: UserDefaults = AppGroupSettings.defaults) {
        defaults.set(true, forKey: key)
    }

    /// Test-only / Advanced "Reset migration" support.
    static func clear(defaults: UserDefaults = AppGroupSettings.defaults) {
        defaults.removeObject(forKey: key)
    }
}
