import AppKit
import ApplicationServices
import Foundation

/// Per-app AX notifications → capture pipeline refresh (DockDoor `WindowManipulationObservers` subset).
/// Window observers are attached only for hovered / recently-hovered apps, not every regular app.
@MainActor
final class DockPreviewWindowAXCacheObservers {
    private weak var pipeline: DockPreviewWindowCapturePipeline?
    private weak var refreshScope: DockPreviewRefreshScope?
    private var observers: [pid_t: AXObserver] = [:]
    private var observerBoxes: [pid_t: ObserverBox] = [:]
    private var debouncedTasks: [pid_t: Task<Void, Never>] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var spaceChangeTask: Task<Void, Never>?
    private var reconcileTask: Task<Void, Never>?

    /// DockDoor hides the hover panel before re-warming cache on space change.
    var onSpaceWillChange: (() -> Void)?

    func start(pipeline: DockPreviewWindowCapturePipeline, refreshScope: DockPreviewRefreshScope) {
        stop()
        self.pipeline = pipeline
        self.refreshScope = refreshScope
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular
            else { return }
            self?.handleAppLaunched(app)
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.removeObserver(for: app.processIdentifier)
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleWarmAllAfterSpaceChange()
        })
        startReconcileLoop()
    }

    func stop() {
        reconcileTask?.cancel()
        reconcileTask = nil
        spaceChangeTask?.cancel()
        spaceChangeTask = nil
        onSpaceWillChange = nil
        for task in debouncedTasks.values { task.cancel() }
        debouncedTasks = [:]
        for pid in Array(observers.keys) {
            removeObserver(for: pid)
        }
        observerBoxes = [:]
        for token in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceObservers = []
        pipeline = nil
        refreshScope = nil
    }

    func ensureObserver(for pid: pid_t) {
        guard pid != 0,
              let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy == .regular
        else { return }
        createObserver(for: app)
    }

    func reconcileObservers() {
        refreshScope?.pruneExpiredEntries()
        guard let refreshScope else {
            detachAllWindowObservers()
            return
        }
        if refreshScope.isIdle {
            detachAllWindowObservers()
            return
        }
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let keep = Set(apps.map(\.processIdentifier).filter { refreshScope.shouldMaintainWindowObserver(for: $0) })
        for pid in Array(observers.keys) where !keep.contains(pid) {
            removeObserver(for: pid)
        }
        for app in apps where keep.contains(app.processIdentifier) {
            createObserver(for: app)
        }
    }

    private func startReconcileLoop() {
        reconcileTask?.cancel()
        reconcileTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self else { return }
                self.reconcileObservers()
            }
        }
    }

    private func detachAllWindowObservers() {
        for pid in Array(observers.keys) {
            removeObserver(for: pid)
        }
    }

    private func handleAppLaunched(_ app: NSRunningApplication) {
        guard let refreshScope else { return }
        guard !refreshScope.isIdle else { return }
        if refreshScope.shouldRefresh(pid: app.processIdentifier) {
            createObserver(for: app)
            scheduleRefresh(pid: app.processIdentifier, bundleIdentifier: app.bundleIdentifier)
        }
    }

    private func debounceInterval() -> TimeInterval {
        pipeline?.processingDebounceInterval ?? 0.3
    }

    private func scheduleRefresh(pid: pid_t, bundleIdentifier: String?) {
        guard refreshScope?.shouldRefresh(pid: pid) ?? false else { return }
        debouncedTasks[pid]?.cancel()
        debouncedTasks[pid] = Task { @MainActor [weak self] in
            let delay = self?.debounceInterval() ?? 0.3
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled, let self else { return }
            guard self.refreshScope?.shouldRefresh(pid: pid) ?? false else { return }
            await self.pipeline?.refreshAppIfNeeded(pid: pid, bundleIdentifier: bundleIdentifier)
            self.debouncedTasks[pid] = nil
        }
    }

    private func scheduleWarmAllAfterSpaceChange() {
        spaceChangeTask?.cancel()
        spaceChangeTask = Task { @MainActor [weak self] in
            self?.onSpaceWillChange?()
            let delay = self?.debounceInterval() ?? 0.3
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            await self?.pipeline?.warmAllRunningApps()
            self?.spaceChangeTask = nil
        }
    }

    private func createObserver(for app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard observers[pid] == nil else { return }
        var observer: AXObserver?
        let box = ObserverBox(owner: self, pid: pid)
        observerBoxes[pid] = box
        let refcon = Unmanaged.passUnretained(box).toOpaque()
        guard AXObserverCreate(pid, Self.axCallback, &observer) == .success, let observer else {
            observerBoxes[pid] = nil
            return
        }
        let appElement = AXUIElementCreateApplication(pid)
        let notifications: [String] = [
            kAXWindowCreatedNotification as String,
            kAXUIElementDestroyedNotification as String,
            kAXWindowMiniaturizedNotification as String,
            kAXWindowDeminiaturizedNotification as String,
            kAXWindowMovedNotification as String,
            kAXWindowResizedNotification as String,
            kAXTitleChangedNotification as String,
        ]
        for name in notifications {
            AXObserverAddNotification(observer, appElement, name as CFString, refcon)
        }
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
        observers[pid] = observer
    }

    private func removeObserver(for pid: pid_t) {
        debouncedTasks[pid]?.cancel()
        debouncedTasks[pid] = nil
        guard let observer = observers.removeValue(forKey: pid) else {
            observerBoxes[pid] = nil
            return
        }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
        observerBoxes[pid] = nil
    }

    private static let axCallback: AXObserverCallback = { _, element, notification, refcon in
        guard let refcon else { return }
        let box = Unmanaged<ObserverBox>.fromOpaque(refcon).takeUnretainedValue()
        Task { @MainActor in
            box.owner?.handleWindowNotification(element: element, notification: notification, pid: box.pid)
        }
    }

    fileprivate func handleWindowNotification(element: AXUIElement, notification: CFString, pid: pid_t) {
        let name = notification as String
        if name == kAXUIElementDestroyedNotification as String {
            if let windowID = SystemDockPreviewPrivateAPI().axWindowID(for: element) {
                pipeline?.removeCachedWindow(windowID: windowID, pid: pid)
            }
            return
        }
        if name == kAXTitleChangedNotification as String {
            guard let role = DockPreviewAXAttributes.string(element, kAXRoleAttribute as String),
                  role == kAXWindowRole as String
            else { return }
        }
        guard refreshScope?.shouldRefresh(pid: pid) ?? false else { return }
        let app = NSRunningApplication(processIdentifier: pid)
        scheduleRefresh(pid: pid, bundleIdentifier: app?.bundleIdentifier)
    }

    private final class ObserverBox {
        weak var owner: DockPreviewWindowAXCacheObservers?
        let pid: pid_t
        init(owner: DockPreviewWindowAXCacheObservers, pid: pid_t) {
            self.owner = owner
            self.pid = pid
        }
    }
}
