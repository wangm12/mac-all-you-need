import Core
import Foundation

enum DockHubSettingsStore {
    private static let settingsKey = "dockPreviews.settings"
    private static let hubKey = "dockPreviews.hub"

    static func load(from defaults: UserDefaults = AppGroupSettings.defaults) -> DockHubSettings {
        if let data = defaults.data(forKey: hubKey),
           let decoded = try? JSONDecoder().decode(DockHubSettings.self, from: data) {
            return decoded
        }
        return migrateLegacy(from: defaults)
    }

    static func save(_ settings: DockHubSettings, to defaults: UserDefaults = AppGroupSettings.defaults) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: hubKey)
        // Keep legacy blob in sync for previews-only readers.
        if let previewData = try? JSONEncoder().encode(settings.previews) {
            defaults.set(previewData, forKey: settingsKey)
        }
        NotificationCenter.default.post(name: .dockPreviewSettingsDidChange, object: nil)
        NotificationCenter.default.post(name: .dockHubSettingsDidChange, object: nil)
    }

    static func loadPreviews(from defaults: UserDefaults = AppGroupSettings.defaults) -> DockPreviewSettings {
        load(from: defaults).previews
    }

    static func savePreviews(_ previews: DockPreviewSettings, to defaults: UserDefaults = AppGroupSettings.defaults) {
        var hub = load(from: defaults)
        hub.previews = previews
        save(hub, to: defaults)
    }

    private static func migrateLegacy(from defaults: UserDefaults) -> DockHubSettings {
        var hub = DockHubSettings.default

        if let data = defaults.data(forKey: settingsKey),
           let previews = try? JSONDecoder().decode(DockPreviewSettings.self, from: data) {
            hub.previews = previews
        } else if let legacy = DockPreviewSettingsStore.migrateLegacyKeysOnly(from: defaults) {
            hub.previews = legacy
        }

        if let data = defaults.data(forKey: "windowSwitcher.settings"),
           let switcher = try? JSONDecoder().decode(LegacyWindowSwitcherSettings.self, from: data) {
            hub.master.enableWindowSwitcher = switcher.enabled
            hub.switcher.shortcutKeyCode = switcher.shortcut.keyCode
            hub.switcher.shortcutModifiers = UInt32(switcher.shortcut.modifierFlags)
        }

        if defaults.object(forKey: "features.windowSwitcher.enabled") != nil {
            hub.master.enableWindowSwitcher = defaults.bool(forKey: "features.windowSwitcher.enabled")
        }
        if defaults.object(forKey: "features.cmdTabEnhancements.enabled") != nil {
            hub.master.enableCmdTabEnhancements = defaults.bool(forKey: "features.cmdTabEnhancements.enabled")
        }
        if defaults.object(forKey: "features.dockLocking.enabled") != nil {
            hub.master.enableDockLocking = defaults.bool(forKey: "features.dockLocking.enabled")
        }
        if defaults.object(forKey: "features.activeAppIndicator.enabled") != nil {
            hub.master.enableActiveAppIndicator = defaults.bool(forKey: "features.activeAppIndicator.enabled")
        }

        if let data = defaults.data(forKey: "dockLocking.settings"),
           let lock = try? JSONDecoder().decode(LegacyDockLockingSettings.self, from: data) {
            hub.master.enableDockLocking = lock.enabled
            hub.dockLock.lockedScreenIdentifier = lock.lockedScreenIdentifier
        }

        if let data = defaults.data(forKey: "activeAppIndicator.settings"),
           let indicator = try? JSONDecoder().decode(LegacyActiveAppIndicatorSettings.self, from: data) {
            hub.master.enableActiveAppIndicator = indicator.enabled
            hub.indicator.colorHex = indicator.colorHex
            hub.indicator.height = indicator.height
            hub.indicator.offset = indicator.offset
        }

        hub.previews.enableFolderWidget = hub.widgets.enableFolderWidget
        hub.previews.folderShowHiddenFiles = hub.widgets.folderShowHiddenFiles

        save(hub, to: defaults)
        return hub
    }
}

private struct LegacyDockLockingSettings: Codable {
    var enabled: Bool
    var lockedScreenIdentifier: String?
}

private struct LegacyActiveAppIndicatorSettings: Codable {
    var enabled: Bool
    var colorHex: String
    var height: Double
    var offset: Double
}

private struct LegacyWindowSwitcherSettings: Codable {
    struct Shortcut: Codable {
        var keyCode: UInt16
        var modifierFlags: UInt
    }

    var enabled: Bool
    var shortcut: Shortcut
}

extension Notification.Name {
    static let dockHubSettingsDidChange = Notification.Name("dockHubSettingsDidChange")
}

extension DockPreviewSettingsStore {
    static func migrateLegacyKeysOnly(from defaults: UserDefaults) -> DockPreviewSettings? {
        var settings = DockPreviewSettings.default
        var migrated = false
        if defaults.object(forKey: "dockPreviews.showThumbnails") != nil {
            settings.showThumbnails = defaults.bool(forKey: "dockPreviews.showThumbnails")
            migrated = true
        }
        if defaults.object(forKey: "dockPreviews.hoverDelayMS") != nil {
            settings.hoverDelayMS = defaults.integer(forKey: "dockPreviews.hoverDelayMS")
            migrated = true
        }
        return migrated ? settings : nil
    }

    static func load(from defaults: UserDefaults = AppGroupSettings.defaults) -> DockPreviewSettings {
        DockHubSettingsStore.loadPreviews(from: defaults)
    }

    static func save(_ settings: DockPreviewSettings, to defaults: UserDefaults = AppGroupSettings.defaults) {
        DockHubSettingsStore.savePreviews(settings, to: defaults)
    }
}
