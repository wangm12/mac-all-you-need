import AppKit
import Foundation

/// Discovers windows for a PID using one enumeration pass; pairs with `DockWindowCache`.
@MainActor
enum DockWindowDiscovery {
    private static let enumerator: any WindowEnumerating = SystemWindowEnumerator()

    static func fetchWindows(
        for pid: pid_t,
        settings: DockPreviewSettings,
        bundleIdentifier: String?
    ) async -> [DockPreviewWindowEntry] {
        await enumerator.windows(
            for: pid,
            settings: settings,
            bundleIdentifier: bundleIdentifier
        )
    }

    static func runningRegularApplications(excludingSelf: Bool = true) -> [NSRunningApplication] {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular && (!excludingSelf || app.processIdentifier != selfPID)
        }
    }
}
