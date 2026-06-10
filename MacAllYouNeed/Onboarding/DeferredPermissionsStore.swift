import Core
import FeatureCore
import Foundation

enum DeferredPermissionsStore {
    private static let key = "onboarding.deferredPermissions"

    static func load(from defaults: UserDefaults = AppGroupSettings.defaults) -> Set<Permission> {
        guard let raw = defaults.stringArray(forKey: key) else { return [] }
        return Set(raw.compactMap(Permission.init(rawValue:)))
    }

    static func save(_ permissions: Set<Permission>, to defaults: UserDefaults = AppGroupSettings.defaults) {
        defaults.set(permissions.map(\.rawValue).sorted(), forKey: key)
    }

    static func reset(in defaults: UserDefaults = AppGroupSettings.defaults) {
        defaults.removeObject(forKey: key)
    }

    static func markDeferred(_ permission: Permission, to defaults: UserDefaults = AppGroupSettings.defaults) {
        var current = load(from: defaults)
        current.insert(permission)
        save(current, to: defaults)
    }
}
