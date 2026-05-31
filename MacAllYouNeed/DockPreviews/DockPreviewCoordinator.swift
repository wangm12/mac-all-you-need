import AppKit
import ApplicationServices
import Foundation
import Platform

@MainActor
@Observable
final class DockPreviewCoordinator {
    private let observer: DockHoverObserver
    private let enumerator: any WindowEnumerating
    private let thumbnailService: any ThumbnailCapturing
    private let cache: DockPreviewWindowCache
    private var thumbnailCache: DockPreviewThumbnailCache
    private let raiseService: DockPreviewRaiseService
    private let panel: DockPreviewPanel
    private let folderPanel: DockPreviewFolderPanel
    private let liveCapture = DockPreviewLiveCaptureManager.shared

    private var settings = DockPreviewSettingsStore.load()
    private var currentHover: DockHoverTarget = .none
    private var currentPID: pid_t?
    private var currentAppName = ""
    private var currentAppIcon: NSImage?
    private var placementAnchorRect: CGRect = .zero
    /// AX icon frame frozen when the preview opens (DockDoor `anchoredDockItem`).
    private var anchoredAXIconRect: CGRect?
    private var currentDockItemToken: UInt?
    private var isRunning = false
    private var showWorkItem: DispatchWorkItem?
    private var showWorkToken: UInt = 0
    private var windowRefreshTask: Task<Void, Never>?
    private var thumbnailTasks: [CGWindowID: Task<Void, Never>] = [:]
    private var settingsObserver: NSObjectProtocol?
    private var mouseMonitors: [Any] = []
    private var outsidePreviewSince: Date?
    private var dismissalPollTask: Task<Void, Never>?
    private var lastLoggedDismissSnapshot: String?

    init(coordinator axCoordinator: AXObserverCoordinator) {
        observer = DockHoverObserver(coordinator: axCoordinator)
        enumerator = SystemWindowEnumerator()
        thumbnailService = DockPreviewThumbnailService()
        cache = DockPreviewWindowCache()
        thumbnailCache = DockPreviewThumbnailCache(ttl: DockPreviewSettings.default.thumbnailCacheLifespan)
        raiseService = DockPreviewRaiseService(enumerator: enumerator)
        panel = DockPreviewPanel()
        folderPanel = DockPreviewFolderPanel()
    }

    func reloadSettings() {
        settings = DockPreviewSettingsStore.load()
        thumbnailCache = DockPreviewThumbnailCache(ttl: settings.thumbnailCacheLifespan)
        observer.settings = { [weak self] in self?.settings ?? .default }
    }

    func start() {
        guard !isRunning else { return }
        guard AXIsProcessTrusted() else { return }
        isRunning = true
        reloadSettings()
        DockPreviewWorklog.log("runtime.start", fields: [
            "axTrusted": AXIsProcessTrusted(),
            "worklog": settings.enableWorklog,
        ])
        observer.settings = { [weak self] in self?.settings ?? .default }
        observer.onHoverBegan = { [weak self] target in
            self?.handleHoverBegan(target)
        }
        observer.onHoverEnded = { [weak self] in
            self?.handleHoverEnded()
        }
        observer.start()
        DockPreviewLaunchSeeder.seed(cache: cache, enumerator: enumerator, settings: settings)
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .dockPreviewSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadSettings()
        }
        startDismissalMonitoring()
        installPointerEventMonitors()
    }

    func stop() {
        DockPreviewWorklog.log("runtime.stop")
        isRunning = false
        stopDismissalMonitoring()
        removePointerEventMonitors()
        showWorkItem?.cancel()
        showWorkItem = nil
        stopDismissalMonitoring()
        windowRefreshTask?.cancel()
        windowRefreshTask = nil
        cancelThumbnailTasks()
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        settingsObserver = nil
        observer.stop()
        panel.dismiss(animated: false)
        folderPanel.dismiss()
        liveCapture.stopAll()
        cache.clearAll()
        thumbnailCache.invalidateAll()
        currentPID = nil
        currentHover = .none
    }

    func refreshPermissions() {
        if panel.isVisible, let pid = currentPID {
            mergePanel(for: pid, reposition: false)
        }
    }

    private func handleHoverBegan(_ target: DockHoverTarget) {
        showWorkItem?.cancel()
        lastLoggedDismissSnapshot = nil

        switch target {
        case .folder(let info):
            DockPreviewWorklog.log("hover.folder", fields: [
                "title": info.title,
                "token": info.dockItemToken,
            ])
            cancelThumbnailTasks()
            windowRefreshTask?.cancel()
            panel.dismiss(animated: false)
            liveCapture.stopAll()
            currentHover = target
            currentDockItemToken = info.dockItemToken
            freezePlacementAnchor(axIconRect: info.iconRect, dockItemToken: info.dockItemToken)
            folderPanel.show(
                title: info.title,
                url: info.url,
                showHidden: settings.folderShowHiddenFiles,
                anchorRect: info.iconRect,
                dockEdge: DockPreviewDockPosition.currentEdge()
            )
        case .app(let info):
            DockPreviewWorklog.log("hover.app", fields: [
                "app": info.appName,
                "pid": info.pid,
                "token": info.dockItemToken,
            ])
            folderPanel.dismiss()
            let switchingIcons = panel.isVisible && currentDockItemToken != info.dockItemToken
            cancelThumbnailTasks()
            windowRefreshTask?.cancel()
            currentHover = target
            currentPID = info.pid
            currentAppName = info.appName
            if switchingIcons || currentDockItemToken != info.dockItemToken {
                anchoredAXIconRect = nil
            }
            currentDockItemToken = info.dockItemToken
            currentAppIcon = info.pid != 0
                ? NSWorkspace.shared.runningApplications.first { $0.processIdentifier == info.pid }?.icon
                : nil

            if info.pid == 0 {
                if settings.showWindowlessApps {
                    let delay = switchingIcons ? 0 : settings.hoverDelay
                    scheduleShow(delay: delay, dockItemToken: info.dockItemToken) { [weak self] in
                        self?.showWindowlessApp(info)
                    }
                }
                return
            }

            if switchingIcons || (panel.isVisible && settings.skipDelayWhenPanelVisible) {
                presentCachedThenRefresh(pid: info.pid, iconRect: info.iconRect, reposition: true)
                scheduleWindowRefresh(for: info.pid, iconRect: info.iconRect, debounce: switchingIcons ? 0.05 : 0)
                return
            }

            let cached = cache.readCached(pid: info.pid)
            if !cached.isEmpty {
                presentCachedThenRefresh(pid: info.pid, iconRect: info.iconRect, reposition: true)
                scheduleWindowRefresh(for: info.pid, iconRect: info.iconRect, debounce: 0.15)
                return
            }

            scheduleShow(delay: settings.hoverDelay, dockItemToken: info.dockItemToken) { [weak self] in
                self?.presentCachedThenRefresh(pid: info.pid, iconRect: info.iconRect, reposition: true)
                self?.scheduleWindowRefresh(for: info.pid, iconRect: info.iconRect, debounce: 0)
            }
        case .none:
            DockPreviewWorklog.log("hover.none")
            handleHoverEnded()
        }
    }

    private func handleHoverEnded() {
        logDismissSnapshot(trigger: "hoverEnded")
        showWorkItem?.cancel()
        showWorkItem = nil
        // AX selection cleared — dismiss unless the cursor is still on the preview surface.
        if isPointerOnPreviewSurfaceOnly() {
            DockPreviewWorklog.log("hoverEnded.keepOnSurface")
            return
        }
        dismissVisiblePreviewIfNeeded(reason: "hoverEnded")
    }

    private func scheduleShow(delay: TimeInterval, dockItemToken: UInt, action: @escaping () -> Void) {
        showWorkToken &+= 1
        let token = showWorkToken
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            defer {
                if self.showWorkToken == token {
                    self.showWorkItem = nil
                }
            }
            guard self.currentDockItemToken == dockItemToken else { return }
            action()
        }
        showWorkItem = work
        if delay <= 0 {
            work.perform()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func dismissImmediately(animated: Bool = true, reason: String = "unspecified") {
        DockPreviewWorklog.log("dismiss", fields: [
            "reason": reason,
            "animated": animated,
            "pid": currentPID ?? 0,
            "token": currentDockItemToken ?? 0,
        ])
        showWorkItem?.cancel()
        showWorkItem = nil
        outsidePreviewSince = nil
        lastLoggedDismissSnapshot = nil
        windowRefreshTask?.cancel()
        windowRefreshTask = nil
        cancelThumbnailTasks()
        panel.dismiss(animated: animated)
        folderPanel.dismiss()
        liveCapture.stopAll()
        currentPID = nil
        currentHover = .none
        currentDockItemToken = nil
        placementAnchorRect = .zero
        anchoredAXIconRect = nil
    }

    private func isPointerOnPreviewSurfaceOnly() -> Bool {
        DockPreviewDockMouse.isPointerOnPreviewSurface(
            panelFrame: panel.isVisible ? panel.panelFrame : nil,
            folderFrame: folderPanel.isVisible ? folderPanel.panelFrame : nil,
            axIconRect: placementAnchorRect
        )
    }

    private func shouldKeepPreviewOpen() -> Bool {
        DockPreviewDockMouse.shouldKeepPreviewOpen(
            axIconRect: placementAnchorRect,
            activeDockItemToken: currentDockItemToken,
            hoveredDockItemToken: observer.currentHoveredDockItemToken(),
            panelFrame: panel.isVisible ? panel.panelFrame : nil,
            folderFrame: folderPanel.isVisible ? folderPanel.panelFrame : nil
        )
    }

    private func dismissVisiblePreviewIfNeeded(animated: Bool = false, reason: String = "pointer") {
        guard panel.isVisible || folderPanel.isVisible else { return }
        dismissImmediately(animated: animated, reason: reason)
    }

    /// DockDoor-style inactivity polling while a preview is visible.
    private func startDismissalMonitoring() {
        dismissalPollTask?.cancel()
        dismissalPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, self.isRunning else { continue }
                self.evaluatePreviewDismissal()
            }
        }
    }

    private func stopDismissalMonitoring() {
        dismissalPollTask?.cancel()
        dismissalPollTask = nil
        outsidePreviewSince = nil
    }

    private func evaluatePreviewDismissal() {
        if showWorkItem != nil, !shouldKeepPreviewOpen() {
            DockPreviewWorklog.log("show.cancelled", details: "left hover zone before delay elapsed")
            showWorkItem?.cancel()
            showWorkItem = nil
        }

        guard panel.isVisible || folderPanel.isVisible else {
            outsidePreviewSince = nil
            return
        }

        logDismissSnapshot(trigger: "poll")

        if shouldKeepPreviewOpen() {
            outsidePreviewSince = nil
            return
        }

        let now = Date()
        if outsidePreviewSince == nil {
            outsidePreviewSince = now
            DockPreviewWorklog.log("dismiss.arm", fields: ["afterMS": settings.dismissInactivityMS])
        }
        let elapsed = now.timeIntervalSince(outsidePreviewSince!)
        if elapsed >= settings.dismissInactivity {
            dismissVisiblePreviewIfNeeded(
                animated: settings.fadeOutDuration > 0,
                reason: "inactivity"
            )
        }
    }

    private func logDismissSnapshot(trigger: String) {
        let keep = shouldKeepPreviewOpen()
        let onSurface = isPointerOnPreviewSurfaceOnly()
        let snapshot = "keep=\(keep) surface=\(onSurface) panel=\(panel.isVisible) folder=\(folderPanel.isVisible) active=\(currentDockItemToken ?? 0) hover=\(observer.currentHoveredDockItemToken() ?? 0)"
        guard snapshot != lastLoggedDismissSnapshot else { return }
        lastLoggedDismissSnapshot = snapshot
        DockPreviewWorklog.log("dismiss.state", fields: [
            "trigger": trigger,
            "keepOpen": keep,
            "onSurface": onSurface,
            "panelVisible": panel.isVisible,
            "folderVisible": folderPanel.isVisible,
            "activeToken": currentDockItemToken ?? 0,
            "hoverToken": observer.currentHoveredDockItemToken() ?? 0,
            "outsideMS": outsidePreviewSince.map { Int(Date().timeIntervalSince($0) * 1000) } ?? -1,
        ])
    }

    private func installPointerEventMonitors() {
        removePointerEventMonitors()
        let clickMask: NSEvent.EventTypeMask = [.rightMouseDown, .otherMouseDown, .leftMouseDown]
        let moveMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]

        for mask in [clickMask, moveMask] {
            if let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
                Task { @MainActor in self?.handlePointerEvent(event) }
            } {
                mouseMonitors.append(global)
            }
            if let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                Task { @MainActor in self?.handlePointerEvent(event) }
                return event
            } {
                mouseMonitors.append(local)
            }
        }
    }

    private func removePointerEventMonitors() {
        for monitor in mouseMonitors {
            NSEvent.removeMonitor(monitor)
        }
        mouseMonitors = []
    }

    private func handlePointerEvent(_ event: NSEvent) {
        guard isRunning else { return }
        switch event.type {
        case .rightMouseDown, .otherMouseDown:
            handleContextMenuMouseDown(event)
        case .leftMouseDown:
            if isSecondaryClickEvent(event) {
                handleContextMenuMouseDown(event)
            }
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            evaluatePreviewDismissal()
        default:
            break
        }
    }

    private func handleContextMenuMouseDown(_ event: NSEvent) {
        guard isRunning else { return }
        guard isSecondaryClickEvent(event) else { return }

        let nearDock = DockPreviewDockPosition.isMouseInDockRegion(padding: 48)
        let previewActive = panel.isVisible || folderPanel.isVisible || showWorkItem != nil
        guard nearDock || previewActive else { return }

        showWorkItem?.cancel()
        showWorkItem = nil
        dismissImmediately(reason: "contextMenu")
    }

    private func isSecondaryClickEvent(_ event: NSEvent) -> Bool {
        switch event.type {
        case .rightMouseDown, .otherMouseDown:
            return true
        case .leftMouseDown:
            return event.modifierFlags.contains(.control)
        default:
            return false
        }
    }

    private func freezePlacementAnchor(axIconRect: CGRect, dockItemToken: UInt) {
        guard settings.anchorToDockIcon else {
            placementAnchorRect = .zero
            anchoredAXIconRect = nil
            return
        }
        _ = dockItemToken
        if anchoredAXIconRect == nil {
            anchoredAXIconRect = DockPreviewPanelGeometry.frozenPlacementAnchor(axRect: axIconRect)
        }
        placementAnchorRect = anchoredAXIconRect ?? axIconRect
    }

    private func scheduleWindowRefresh(for pid: pid_t, iconRect: CGRect, debounce: TimeInterval) {
        windowRefreshTask?.cancel()
        windowRefreshTask = Task { @MainActor [weak self] in
            if debounce > 0 {
                try? await Task.sleep(for: .seconds(debounce))
            }
            guard !Task.isCancelled, let self else { return }
            guard self.currentPID == pid else { return }
            var entries = await self.enumerator.windows(for: pid, settings: self.settings)
            entries = DockPreviewWindowFilter.filterByMonitor(entries, dockIconRect: iconRect, settings: self.settings)
            guard self.currentPID == pid else { return }
            if entries.isEmpty, !self.settings.showWindowlessApps { return }
            _ = self.cache.update(entries: entries, for: pid)
            self.mergePanel(for: pid, entries: entries, reposition: false)
            self.captureThumbnailsIfNeeded(for: pid, entries: entries)
        }
    }

    private func presentCachedThenRefresh(pid: pid_t, iconRect: CGRect, reposition: Bool) {
        guard case .app = currentHover, currentPID == pid else { return }
        freezePlacementAnchor(axIconRect: iconRect, dockItemToken: currentDockItemToken ?? 0)
        DockPreviewWorklog.log("panel.present", fields: [
            "pid": pid,
            "reposition": reposition,
            "cached": cache.readCached(pid: pid).count,
        ])
        var entries = cache.readCached(pid: pid)
        entries = DockPreviewWindowFilter.filter(entries, settings: settings)
        entries = DockPreviewWindowFilter.filterByMonitor(entries, dockIconRect: iconRect, settings: settings)
        if entries.isEmpty, settings.showWindowlessApps {
            showWindowlessApp(DockHoverTarget.AppHoverInfo(
                pid: pid, appName: currentAppName, bundleIdentifier: nil,
                iconRect: iconRect, dockItemToken: currentDockItemToken ?? 0
            ))
            scheduleWindowRefresh(for: pid, iconRect: iconRect, debounce: 0)
            return
        }
        guard !entries.isEmpty else { return }
        mergePanel(for: pid, entries: entries, reposition: true)
        captureThumbnailsIfNeeded(for: pid, entries: entries)
    }

    private func mergePanel(
        for pid: pid_t,
        entries: [DockPreviewWindowEntry]? = nil,
        reposition: Bool
    ) {
        guard currentPID == pid, case .app = currentHover else { return }
        let list = entries ?? cache.readCached(pid: pid)
        guard !list.isEmpty else { return }
        if !panel.isVisible {
            DockPreviewWorklog.log("panel.show", fields: [
                "pid": pid,
                "windows": list.count,
                "mode": String(describing: DockPreviewPermissionGate.currentMode(settings: settings)),
            ])
        }
        let mode = DockPreviewPermissionGate.currentMode(settings: settings)
        let anchor = settings.anchorToDockIcon ? placementAnchorRect : .zero
        let presentation = DockPreviewPanelPresentation(
            appIcon: currentAppIcon,
            appName: currentAppName,
            entries: list,
            mode: mode,
            anchorRect: anchor,
            dockEdge: DockPreviewDockPosition.currentEdge(),
            enableLivePreview: settings.enableLivePreview
        )
        let placementKey = currentDockItemToken ?? 0
        panel.update(
            presentation: presentation,
            placementKey: placementKey,
            reposition: reposition,
            onSelect: { [weak self] entry in
                Task { @MainActor in
                    await self?.raiseService.raise(entry: entry, settings: self?.settings ?? .default)
                    self?.dismissImmediately(reason: "windowSelected")
                }
            }
        )
        if settings.enableLivePreview, mode == .fullPreview {
            liveCapture.setActiveWindowIDs(list.map(\.id), settings: settings)
        }
    }

    private func captureThumbnailsIfNeeded(for pid: pid_t, entries: [DockPreviewWindowEntry]) {
        guard DockPreviewPermissionGate.currentMode(settings: settings) == .fullPreview else { return }
        for entry in entries {
            if let cached = thumbnailCache.get(windowID: entry.id) {
                cache.setThumbnail(cached, windowID: entry.id, pid: pid)
                continue
            }
            thumbnailTasks[entry.id]?.cancel()
            thumbnailTasks[entry.id] = Task { @MainActor [weak self] in
                guard let self, self.currentPID == pid else { return }
                let scale = CGFloat(self.settings.thumbnailScale)
                if let thumb = await self.thumbnailService.capture(windowID: entry.id, scale: max(1, scale)) {
                    guard self.currentPID == pid else { return }
                    self.thumbnailCache.set(windowID: entry.id, image: thumb)
                    self.cache.setThumbnail(thumb, windowID: entry.id, pid: pid)
                    self.mergePanel(for: pid, reposition: false)
                }
            }
        }
    }

    private func cancelThumbnailTasks() {
        for task in thumbnailTasks.values { task.cancel() }
        thumbnailTasks = [:]
    }

    private func showWindowlessApp(_ info: DockHoverTarget.AppHoverInfo) {
        freezePlacementAnchor(axIconRect: info.iconRect, dockItemToken: info.dockItemToken)
        let placeholder = DockPreviewWindowEntry(
            id: CGWindowID(max(1, info.pid + 1)),
            pid: info.pid,
            title: "No open windows",
            frame: .zero,
            thumbnail: nil,
            isMinimized: false,
            isOnScreen: false
        )
        mergePanel(for: info.pid, entries: [placeholder], reposition: true)
    }
}
