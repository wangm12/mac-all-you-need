import Core
import Foundation

/// Bootstrap helper for the auto-created "Pinned" pinboard.
///
/// The default Pinned list used to be a hidden, reserved-name pinboard with
/// special UI (a separate "📌 Pinned" tab). We've unified it with regular
/// user-created pinboards: it shows up in `availableLists` like any other,
/// can be reordered/deleted, and is the suggested first target in the
/// right-click "Pin to list" menu. This helper creates the list on first
/// launch, preserves an explicit user deletion, and migrates the legacy
/// `__pinned__` name forward.
enum PinnedPinboard {
    /// Display name used after migration. New installs create with this name.
    static let displayName = "Pinned"
    /// Neutral color used so the default Pinned tab does not inherit a
    /// user/system accent color.
    static let displayColor = "#8E8E93"
    static let deletedDefaultKey = "clipboardDock.pinnedPinboardDeleted"
    /// Legacy reserved-name for the old hidden Pinned list. Migrated forward
    /// in `findOrCreate` so existing users keep their pinned items.
    private static let legacyReservedName = "__pinned__"

    /// Find the user's Pinned pinboard, migrating from the legacy reserved
    /// name if present. Creates a fresh one if neither exists and the user has
    /// not deleted the default Pinned board.
    @discardableResult
    static func findOrCreate(
        in store: PinboardStore,
        defaults: UserDefaults = AppGroupSettings.defaults
    ) throws -> Pinboard {
        try findOrCreate(in: store, defaults: defaults, recreateAfterDeletion: false)
    }

    @discardableResult
    static func findOrCreateForPinning(
        in store: PinboardStore,
        defaults: UserDefaults = AppGroupSettings.defaults
    ) throws -> Pinboard {
        try findOrCreate(in: store, defaults: defaults, recreateAfterDeletion: true)
    }

    static func markDeleted(defaults: UserDefaults = AppGroupSettings.defaults) {
        defaults.set(true, forKey: deletedDefaultKey)
    }

    static func isDefaultPinned(_ pinboard: Pinboard) -> Bool {
        pinboard.name == displayName || pinboard.name == legacyReservedName
    }

    private static func findOrCreate(
        in store: PinboardStore,
        defaults: UserDefaults,
        recreateAfterDeletion: Bool
    ) throws -> Pinboard {
        let all = (try? store.list()) ?? []

        // Already migrated.
        if let displayed = all.first(where: { $0.name == displayName }) {
            defaults.removeObject(forKey: deletedDefaultKey)
            return displayed
        }

        // Legacy: rename in place, preserve itemIDs + sort_order.
        if var legacy = all.first(where: { $0.name == legacyReservedName }) {
            legacy.name = displayName
            if legacy.color == nil { legacy.color = displayColor }
            legacy.modified = Date()
            try store.update(legacy)
            defaults.removeObject(forKey: deletedDefaultKey)
            return legacy
        }

        if defaults.bool(forKey: deletedDefaultKey), !recreateAfterDeletion {
            throw NSError(domain: "PinnedPinboard", code: 1)
        }

        // Fresh install.
        let created = try store.create(name: displayName, color: displayColor)
        defaults.removeObject(forKey: deletedDefaultKey)
        return created
    }
}
