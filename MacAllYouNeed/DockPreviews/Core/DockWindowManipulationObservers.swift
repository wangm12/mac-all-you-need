import AppKit
import Foundation

/// Workspace lifecycle hooks for dock preview cache (DockDoor: terminate purges; activate hides panel only).
@MainActor
final class DockWindowManipulationObservers {
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private weak var cache: DockPreviewWindowCache?
    var onInvalidate: (() -> Void)?
    /// DockDoor `appDidActivate` — hide preview, do not clear warmed thumbnails.
    var onApplicationActivated: (() -> Void)?

    func start(cache: DockPreviewWindowCache) {
        stop()
        self.cache = cache
        let center = NSWorkspace.shared.notificationCenter
        observers.append((center, center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleTerminate(note)
        }))
        observers.append((center, center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onApplicationActivated?()
        }))
        let appCenter = NotificationCenter.default
        observers.append((appCenter, appCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.invalidateAll()
        }))
    }

    func stop() {
        for (center, token) in observers {
            center.removeObserver(token)
        }
        observers = []
        cache = nil
        onApplicationActivated = nil
    }

    private func handleTerminate(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        cache?.clear(pid: app.processIdentifier)
        onInvalidate?()
    }

    private func invalidateAll() {
        cache?.clearAll()
        onInvalidate?()
    }
}
