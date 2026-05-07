import Core
import Foundation
import ServiceManagement

enum LoginItemController {
    static let daemonIdentifier = "com.macallyouneed.app.daemon"

    static func reconcileLaunchAtLogin() {
        let enabled = AppGroupSettings.defaults.object(forKey: "launchAtLogin") as? Bool ?? true
        setLaunchAtLogin(enabled)
    }

    static func setLaunchAtLogin(_ enabled: Bool) {
        do {
            let item = SMAppService.loginItem(identifier: daemonIdentifier)
            if enabled { try item.register() } else { try item.unregister() }
            AppGroupSettings.defaults.set(enabled, forKey: "launchAtLogin")
        } catch {
            Logging.logger(for: "app", category: "login-item")
                .error("Login item update failed: \(error.localizedDescription)")
        }
    }
}
