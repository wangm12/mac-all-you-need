import Core
import Foundation

/// Bootstrap helper for the auto-created "Pinned" pinboard.
///
/// The default Pinned list used to be a hidden, reserved-name pinboard with
/// special UI (a separate "📌 Pinned" tab). We've unified it with regular
/// user-created pinboards: it shows up in `availableLists` like any other,
/// can be reordered/deleted, and is the suggested first target in the
/// right-click "Pin to list" menu. This helper just guarantees the list
/// exists on first launch and migrates the legacy `__pinned__` name forward.
enum PinnedPinboard {
    /// Display name used after migration. New installs create with this name.
    static let displayName = "Pinned"
    /// Color hex applied so the dot in the tab bar reads as a pin marker.
    static let displayColor = "#FF3B30"
    /// Legacy reserved-name for the old hidden Pinned list. Migrated forward
    /// in `findOrCreate` so existing users keep their pinned items.
    private static let legacyReservedName = "__pinned__"

    /// Find the user's Pinned pinboard, migrating from the legacy reserved
    /// name if present. Creates a fresh one if neither exists.
    @discardableResult
    static func findOrCreate(in store: PinboardStore) throws -> Pinboard {
        let all = (try? store.list()) ?? []

        // Already migrated.
        if let displayed = all.first(where: { $0.name == displayName }) {
            return displayed
        }

        // Legacy: rename in place, preserve itemIDs + sort_order.
        if var legacy = all.first(where: { $0.name == legacyReservedName }) {
            legacy.name = displayName
            if legacy.color == nil { legacy.color = displayColor }
            legacy.modified = Date()
            try store.update(legacy)
            return legacy
        }

        // Fresh install.
        return try store.create(name: displayName, color: displayColor)
    }
}
