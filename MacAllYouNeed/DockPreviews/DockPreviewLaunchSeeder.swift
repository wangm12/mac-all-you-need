import AppKit
import Foundation

enum DockPreviewLaunchSeeder {
    static func seed(
        cache: DockPreviewWindowCache,
        enumerator: any WindowEnumerating,
        settings: DockPreviewSettings,
        maxApps: Int = 12
    ) {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != selfPID }
        let targetApps = maxApps >= apps.count ? apps : Array(apps.prefix(maxApps))
        Task.detached {
            await withTaskGroup(of: Void.self) { group in
                for app in targetApps {
                    group.addTask {
                        let entries = await enumerator.windows(
                            for: app.processIdentifier,
                            settings: settings,
                            bundleIdentifier: app.bundleIdentifier
                        )
                        await MainActor.run {
                            _ = cache.update(entries: entries, for: app.processIdentifier)
                        }
                    }
                }
            }
        }
    }
}
