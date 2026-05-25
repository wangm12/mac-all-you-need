import AppKit
import Core
import Foundation

/// One-time cleanup for legacy clipboard "ignored apps" lists that shipped with
/// recommended password-manager bundle IDs. Those rows show placeholder icons when
/// the apps are not installed; keep only bundle IDs that resolve to an app on disk.
public enum ClipboardExcludedAppsPruner {
    private static let bundleIDsKey = "clipboardExcludedBundleIDs"
    private static let migrationKey = "clipboardExcludedBundleIDs.prunedToInstalledApps.v1"

    public static func migrateIfNeeded(defaults: UserDefaults = AppGroupSettings.defaults) {
        guard !defaults.bool(forKey: migrationKey) else { return }

        defer { defaults.set(true, forKey: migrationKey) }

        guard let rawIDs = defaults.stringArray(forKey: bundleIDsKey), !rawIDs.isEmpty else { return }

        let trimmedIDs = rawIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let installed = trimmedIDs.filter { bundleID in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
        }
        let normalized = Array(Set(installed)).sorted()

        guard Set(normalized) != Set(trimmedIDs) else { return }

        defaults.set(normalized, forKey: bundleIDsKey)

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.macallyouneed.settings-changed" as CFString),
            nil,
            nil,
            true
        )
    }
}
