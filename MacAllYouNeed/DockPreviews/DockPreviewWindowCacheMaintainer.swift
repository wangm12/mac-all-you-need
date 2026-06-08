import AppKit
import Foundation

/// Keeps per-PID window caches warm when apps create/destroy windows (DockDoor `WindowManipulationObservers` subset).
@MainActor
final class DockPreviewWindowCacheMaintainer {
    private let cache: DockPreviewWindowCache
    private let pipeline: DockPreviewWindowCapturePipeline
    private weak var refreshScope: DockPreviewRefreshScope?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var refreshTasks: [pid_t: Task<Void, Never>] = [:]

    init(cache: DockPreviewWindowCache, pipeline: DockPreviewWindowCapturePipeline) {
        self.cache = cache
        self.pipeline = pipeline
    }

    func reloadSettings(hub: DockHubSettings? = nil) {
        pipeline.reloadSettings(hub: hub)
    }

    func start(refreshScope: DockPreviewRefreshScope? = nil) {
        stop()
        self.refreshScope = refreshScope
        let center = NSWorkspace.shared.notificationCenter
        observers.append((center, center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.refresh(pid: app.processIdentifier, bundleIdentifier: app.bundleIdentifier)
        }))
        observers.append((center, center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.handleTermination(pid: app.processIdentifier, bundleID: app.bundleIdentifier)
        }))
        let distributed = DistributedNotificationCenter.default()
        observers.append((distributed, distributed.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshAllRunningApps()
        }))
        observers.append((distributed, distributed.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshAllRunningApps()
        }))
    }

    func stop() {
        for (center, token) in observers {
            center.removeObserver(token)
        }
        observers = []
        for task in refreshTasks.values { task.cancel() }
        refreshTasks = [:]
    }

    func refresh(pid: pid_t, bundleIdentifier: String? = nil) {
        guard refreshScope?.shouldRefresh(pid: pid) ?? false else { return }
        refreshTasks[pid]?.cancel()
        refreshTasks[pid] = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.pipeline.refreshApp(pid: pid, bundleIdentifier: bundleIdentifier)
            self.refreshTasks[pid] = nil
        }
    }

    /// Screen lock/unlock and wake recovery — always warm; do not gate on dock-idle scope.
    func refreshAllRunningApps() {
        Task { @MainActor [weak self] in
            await self?.pipeline.warmAllRunningApps(throttle: true)
        }
    }

    private func handleTermination(pid: pid_t, bundleID: String?) {
        refreshTasks[pid]?.cancel()
        refreshTasks[pid] = nil
        cache.clear(pid: pid)
        _ = bundleID
    }
}
