import Core
import Foundation
import ServiceManagement

enum LoginItemController {
    static let daemonIdentifier = "com.macallyouneed.app.daemon"
    static let downloadDaemonIdentifier = "com.macallyouneed.app.downloader"

    static func reconcileLaunchAtLogin() {
        let enabled = AppGroupSettings.defaults.object(forKey: "launchAtLogin") as? Bool ?? true
        setLaunchAtLogin(enabled)
        setDownloadDaemonLaunchAtLogin(enabled)
    }

    static func setLaunchAtLogin(_ enabled: Bool) {
        let item = SMAppService.loginItem(identifier: daemonIdentifier)
        if enabled {
            // Always unregister first to clear any crash-throttle state from macOS,
            // then re-register so the daemon starts fresh on this app launch.
            try? item.unregister()
            do {
                try item.register()
                AppGroupSettings.defaults.set(true, forKey: "launchAtLogin")
            } catch {
                Logging.logger(for: "app", category: "login-item")
                    .error("Login item register failed: \(error.localizedDescription)")
            }
        } else {
            try? item.unregister()
            AppGroupSettings.defaults.set(false, forKey: "launchAtLogin")
        }
    }

    static func setDownloadDaemonLaunchAtLogin(_ enabled: Bool) {
        let item = SMAppService.loginItem(identifier: downloadDaemonIdentifier)
        if enabled {
            try? item.unregister()
            do {
                try item.register()
                AppGroupSettings.defaults.set(true, forKey: "downloadDaemonLaunchAtLogin")
            } catch {
                Logging.logger(for: "app", category: "login-item")
                    .error("Download daemon register failed: \(error.localizedDescription)")
            }
        } else {
            try? item.unregister()
            AppGroupSettings.defaults.set(false, forKey: "downloadDaemonLaunchAtLogin")
        }
    }
}
