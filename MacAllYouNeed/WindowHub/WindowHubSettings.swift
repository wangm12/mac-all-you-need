import Core
import Foundation

struct WindowHubSettings: Codable, Equatable, Sendable {
    var showBackgroundApps = false
    var skipLowRiskConfirmations = false
    var aiSendFullURLs = false
    var preferredBrowseMode = false
    /// When off, Window Hub lists browser windows via Accessibility only and does not
    /// read tab titles/URLs through Automation (avoids macOS app-data prompts).
    var browserTabDiscoveryEnabled = true
    /// Tabs shown per window before collapsing into a "Show all N tabs" row.
    var tabsPerWindow = 10

    static let storageKey = "windowHub.settings"

    /// Clamped, always-valid collapse threshold used by the dashboard.
    var resolvedTabsPerWindow: Int { min(50, max(1, tabsPerWindow)) }
}

enum WindowHubSettingsStore {
    static func load(from defaults: UserDefaults = AppGroupSettings.defaults) -> WindowHubSettings {
        guard let data = defaults.data(forKey: WindowHubSettings.storageKey),
              let decoded = try? JSONDecoder().decode(WindowHubSettings.self, from: data)
        else {
            return WindowHubSettings()
        }
        return decoded
    }

    static func save(_ settings: WindowHubSettings, to defaults: UserDefaults = AppGroupSettings.defaults) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: WindowHubSettings.storageKey)
    }
}
