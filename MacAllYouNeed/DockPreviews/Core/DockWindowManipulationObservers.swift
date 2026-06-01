import AppKit
import Foundation

/// Invalidates window cache on workspace / app lifecycle events (DockDoor `WindowManipulationObservers` behavior).
@MainActor
final class DockWindowManipulationObservers {
    private var observers: [NSObjectProtocol] = []
    private weak var cache: DockPreviewWindowCache?
    var onInvalidate: (() -> Void)?

    func start(cache: DockPreviewWindowCache) {
        stop()
        self.cache = cache
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                self?.handleWorkspace(note)
            }
            observers.append(token)
        }
        let screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.invalidateAll()
        }
        observers.append(screenToken)
    }

    func stop() {
        for token in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            NotificationCenter.default.removeObserver(token)
        }
        observers = []
        cache = nil
    }

    private func handleWorkspace(_ note: Notification) {
        if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            cache?.clear(pid: app.processIdentifier)
        }
        onInvalidate?()
    }

    private func invalidateAll() {
        cache?.clearAll()
        onInvalidate?()
    }
}
