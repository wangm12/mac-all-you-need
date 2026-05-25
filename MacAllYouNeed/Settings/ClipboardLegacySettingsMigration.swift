import Core
import Foundation

/// Older builds stored a separate `clipboardMaxItems` cap for the main Clipboard UI.
/// Retention cleanup already honors `retention.maxItems`; merge the legacy value once
/// so raising the UI cap continues to apply after removing the duplicate control.
enum ClipboardLegacySettingsMigration {
    private static let mergedKey = "clipboard.clipboardMaxItemsMergedToRetention.v1"

    static func mergeClipboardMaxItemsIntoRetentionIfNeeded(defaults: UserDefaults = AppGroupSettings.defaults) {
        guard !defaults.bool(forKey: mergedKey) else { return }
        defer { defaults.set(true, forKey: mergedKey) }

        guard let legacy = defaults.object(forKey: "clipboardMaxItems") as? Int, legacy > 0 else { return }

        let current = defaults.object(forKey: "retention.maxItems") as? Int ?? 1000
        defaults.set(max(current, legacy), forKey: "retention.maxItems")
        defaults.removeObject(forKey: "clipboardMaxItems")
    }
}
