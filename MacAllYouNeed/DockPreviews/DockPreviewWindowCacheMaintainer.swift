import AppKit
import Foundation

/// Keeps per-PID window caches warm when apps create/destroy windows (DockDoor `WindowManipulationObservers` subset).
@MainActor
final class DockPreviewWindowCacheMaintainer {
    private let cache: DockPreviewWindowCache
    private let enumerator: any WindowEnumerating
    private var observers: [NSObjectProtocol] = []
    private var refreshTasks: [pid_t: Task<Void, Never>] = [:]

    init(cache: DockPreviewWindowCache, enumerator: any WindowEnumerating) {
        self.cache = cache
        self.enumerator = enumerator
    }

    func start() {
        stop()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.refresh(pid: app.processIdentifier)
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.handleTermination(pid: app.processIdentifier, bundleID: app.bundleIdentifier)
        })
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshAllRunningApps()
        })
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshAllRunningApps()
        })
    }

    func stop() {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observers = []
        for task in refreshTasks.values { task.cancel() }
        refreshTasks = [:]
    }

    func refresh(pid: pid_t) {
        refreshTasks[pid]?.cancel()
        let settings = DockHubSettingsStore.loadPreviews()
        refreshTasks[pid] = Task { @MainActor [weak self] in
            guard let self else { return }
            let entries = await self.enumerator.windows(for: pid, settings: settings, bundleIdentifier: nil)
            _ = self.cache.update(entries: entries, for: pid)
            self.refreshTasks[pid] = nil
        }
    }

    private func refreshAllRunningApps() {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != selfPID {
            refresh(pid: app.processIdentifier)
        }
    }

    private func handleTermination(pid: pid_t, bundleID: String?) {
        refreshTasks[pid]?.cancel()
        refreshTasks[pid] = nil
        let settings = DockHubSettingsStore.loadPreviews()
        guard !settings.keepPreviewOnAppQuit else { return }
        cache.clear(pid: pid)
    }
}
