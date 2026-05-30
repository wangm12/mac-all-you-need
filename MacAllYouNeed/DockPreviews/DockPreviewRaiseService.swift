import AppKit
import Foundation

@MainActor
final class DockPreviewRaiseService {
    private let api: any DockPreviewPrivateAPI

    init(api: any DockPreviewPrivateAPI = SystemDockPreviewPrivateAPI()) {
        self.api = api
    }

    func raise(entry: DockPreviewWindowEntry) {
        // Activate the app first.
        if let app = NSRunningApplication(processIdentifier: entry.pid) {
            app.activate(options: .activateIgnoringOtherApps)
        }
        // Use private API to bring the owning process / window to front.
        _ = api.raiseWindow(windowID: entry.id, pid: entry.pid)
    }
}
