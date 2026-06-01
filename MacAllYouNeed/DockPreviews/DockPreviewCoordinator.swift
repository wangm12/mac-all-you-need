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
    let cache: DockPreviewWindowCache
    private var thumbnailCache: DockPreviewThumbnailCache
    private let raiseService: DockPreviewRaiseService
    private let panelController: DockPreviewPanelController
    private var panel: DockPreviewPanel { panelController.panel }
    private let liveCapture = DockPreviewLiveCaptureManager.shared
    private let dockAutoHide = DockPreviewDockAutoHideManager()
    private let cacheMaintainer: DockPreviewWindowCacheMaintainer

    private var settings = DockPreviewSettingsStore.load()
    private var hubSettings = DockHubSettings.default
    private var currentHover: DockHoverTarget = .none
    private var currentPID: pid_t?
    private var currentBundleIdentifier: String?
    private var currentAppName = ""
    private var currentAppIcon: NSImage?
    private var placementAnchorRect: CGRect = .zero
    /// AX icon frame frozen when the preview opens (DockDoor `anchoredDockItem`).
    private var anchoredAXIconRect: CGRect?
    private var frozenDockItemToken: UInt?
    private var currentDockItemToken: UInt?
    private var isRunning = false
    private var showWorkItem: DispatchWorkItem?
    private var showWorkToken: UInt = 0
    private var windowRefreshTask: Task<Void, Never>?
    private var thumbnailTasks: [CGWindowID: Task<Void, Never>] = [:]
    private var settingsObserver: NSObjectProtocol?
    private var dismissPreserveObserver: NSObjectProtocol?
    private var mouseMonitors: [Any] = []
    private var terminateObserver: NSObjectProtocol?
    private var lastLoggedDismissSnapshot: String?

    init(panelController: DockPreviewPanelController, coordinator axCoordinator: AXObserverCoordinator) {
        self.panelController = panelController
        observer = DockHoverObserver(coordinator: axCoordinator)
        enumerator = SystemWindowEnumerator()
        thumbnailService = DockPreviewThumbnailService()
        cache = DockPreviewWindowCache()
        cacheMaintainer = DockPreviewWindowCacheMaintainer(cache: cache, enumerator: enumerator)
        thumbnailCache = DockPreviewThumbnailCache(ttl: DockPreviewSettings.default.thumbnailCacheLifespan)
        raiseService = DockPreviewRaiseService(enumerator: enumerator)
        panel.onDismissRequest = { [weak self] in self?.handleInactivityDismiss() }
        panel.shouldKeepOpen = { [weak self] in self?.shouldKeepPreviewOpen() ?? false }
    }

    func reloadSettings(hub: DockHubSettings? = nil) {
        let loadedHub = hub ?? DockHubSettingsStore.load()
        hubSettings = loadedHub
        settings = loadedHub.previews
        panelController.reloadSettings(loadedHub)
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
        DockHoverObserver.lastHoveredTokenProvider = { [weak self] in
            self?.observer.currentHoveredDockItemToken()
        }
        observer.start()
        DockPreviewLaunchSeeder.seed(cache: cache, enumerator: enumerator, settings: settings)
        cacheMaintainer.start()
        terminateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleApplicationTerminated(note)
        }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .dockPreviewSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadSettings()
        }
        dismissPreserveObserver = NotificationCenter.default.addObserver(
            forName: .dockPreviewPanelDismissPreservePendingShow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.dismissImmediately(animated: true, reason: "dockIconTransition", cancelPendingShow: false)
        }
        installPointerEventMonitors()
    }

    func stop() {
        DockPreviewWorklog.log("runtime.stop")
        isRunning = false
        cacheMaintainer.stop()
        if let terminateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminateObserver)
        }
        terminateObserver = nil
        dockAutoHide.restoreIfNeeded()
        removePointerEventMonitors()
        showWorkItem?.cancel()
        showWorkItem = nil
        windowRefreshTask?.cancel()
        windowRefreshTask = nil
        cancelThumbnailTasks()
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        settingsObserver = nil
        if let dismissPreserveObserver {
            NotificationCenter.default.removeObserver(dismissPreserveObserver)
        }
        dismissPreserveObserver = nil
        observer.stop()
        panel.dismiss(animated: false)
        liveCapture.stopAll()
        cache.clearAll()
        thumbnailCache.invalidateAll()
        currentPID = nil
        currentBundleIdentifier = nil
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
            liveCapture.stopAll()
            currentHover = target
            currentPID = 0
            currentDockItemToken = info.dockItemToken
            freezePlacementAnchor(axIconRect: info.iconRect, dockItemToken: info.dockItemToken)
            panelController.state.embeddedContent = .folder(title: info.title, url: info.url)
            panelController.state.appearance = DockPreviewAppearanceContext.resolve(mode: .dockHover, settings: settings)
            presentFolderPreview(info: info)
        case .app(let info):
            DockPreviewWorklog.log("hover.app", fields: [
                "app": info.appName,
                "pid": info.pid,
                "token": info.dockItemToken,
            ])
            panelController.state.embeddedContent = DockPreviewEmbedRouting.embeddedContent(
                bundleIdentifier: info.bundleIdentifier,
                widgets: hubSettings.widgets
            )
            panelController.state.appearance = DockPreviewAppearanceContext.resolve(mode: .dockHover, settings: settings)

            if panel.mouseIsWithinPreview,
               let displayedPID = currentPID,
               displayedPID != 0,
               info.pid != 0,
               displayedPID != info.pid {
                return
            }

            if panel.isVisible,
               currentDockItemToken == info.dockItemToken,
               currentPID == info.pid {
                freezePlacementAnchor(axIconRect: info.iconRect, dockItemToken: info.dockItemToken)
                scheduleWindowRefresh(for: info.pid, iconRect: info.iconRect, debounce: 0.05)
                return
            }

            let switchingIcons = panel.isVisible && currentDockItemToken != info.dockItemToken
            let cachedForPID = cache.readCached(pid: info.pid)
            cancelThumbnailTasks(except: Set(cachedForPID.map(\.id)))
            windowRefreshTask?.cancel()
            if switchingIcons {
                liveCapture.stopAll()
            }
            currentHover = target
            currentPID = info.pid
            currentBundleIdentifier = info.bundleIdentifier
            currentAppName = info.appName
            currentDockItemToken = info.dockItemToken
            currentAppIcon = info.pid != 0
                ? NSWorkspace.shared.runningApplications.first { $0.processIdentifier == info.pid }?.icon
                : nil

            if info.pid == 0 {
                if settings.showWindowlessApps {
                    let delay = hoverDelayForPresent(switchingIcons: switchingIcons)
                    scheduleShow(delay: delay, dockItemToken: info.dockItemToken, expectedPID: 0) { [weak self] in
                        self?.showWindowlessApp(info)
                    }
                }
                return
            }

            guard DockPreviewDockVisibility.isDockVisible() else {
                DockPreviewWorklog.log("panel.suppressed", fields: ["reason": "dockHidden"])
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

            scheduleShow(
                delay: hoverDelayForPresent(switchingIcons: false),
                dockItemToken: info.dockItemToken,
                expectedPID: info.pid
            ) { [weak self] in
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

    private func isExpectedAppStillHovered(bundleID: String) -> Bool {
        guard let token = observer.currentHoveredDockItemToken(),
              token == currentDockItemToken
        else { return false }
        return currentBundleIdentifier == bundleID
    }

    private func hoverDelayForPresent(switchingIcons: Bool) -> TimeInterval {
        if switchingIcons { return 0 }
        if settings.useDelayOnlyForInitialOpen, panel.isVisible { return 0 }
        if panel.isVisible, settings.skipDelayWhenPanelVisible { return 0 }
        return settings.hoverDelay
    }

    private func scheduleShow(
        delay: TimeInterval,
        dockItemToken: UInt,
        expectedPID: pid_t,
        action: @escaping () -> Void
    ) {
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
            guard self.currentPID == expectedPID else { return }
            guard DockPreviewDockVisibility.isDockVisible() else { return }
            if expectedPID != 0,
               let bundleID = self.currentBundleIdentifier,
               !self.isExpectedAppStillHovered(bundleID: bundleID) {
                return
            }
            action()
        }
        showWorkItem = work
        if delay <= 0 {
            work.perform()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func dismissImmediately(
        animated: Bool = true,
        reason: String = "unspecified",
        cancelPendingShow: Bool = true
    ) {
        DockPreviewWorklog.log("dismiss", fields: [
            "reason": reason,
            "animated": animated,
            "pid": currentPID ?? 0,
            "token": currentDockItemToken ?? 0,
        ])
        if cancelPendingShow {
            showWorkItem?.cancel()
            showWorkItem = nil
        }
        lastLoggedDismissSnapshot = nil
        windowRefreshTask?.cancel()
        windowRefreshTask = nil
        cancelThumbnailTasks()
        dockAutoHide.restoreIfNeeded()
        panel.dismiss(animated: animated)
        liveCapture.scheduleStopAfterKeepAlive(settings: settings)
        currentPID = nil
        currentBundleIdentifier = nil
        currentHover = .none
        currentDockItemToken = nil
        placementAnchorRect = .zero
        anchoredAXIconRect = nil
        frozenDockItemToken = nil
    }

    private func handleInactivityDismiss() {
        guard panel.isVisible else { return }
        if shouldKeepPreviewOpen() {
            if !settings.preventPreviewReentryDuringFadeOut {
                panel.resetFadeState()
            }
            return
        }
        let animated = settings.fadeOutDuration > 0
        guard animated else {
            dismissVisiblePreviewIfNeeded(animated: false, reason: "inactivity")
            return
        }
        panel.beginFadeOut(duration: settings.fadeOutDuration) { [weak self] in
            self?.dismissVisiblePreviewIfNeeded(animated: false, reason: "inactivity")
        }
    }

    private func handleApplicationTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        guard app.processIdentifier == currentPID else { return }
        if settings.keepPreviewOnAppQuit { return }
        dismissImmediately(reason: "appTerminated")
    }

    private func isPointerOnPreviewSurfaceOnly() -> Bool {
        DockPreviewDockMouse.isPointerOnPreviewSurface(
            panelFrame: panel.isVisible ? panel.panelFrame : nil,
            folderFrame: nil,
            axIconRect: placementAnchorRect
        )
    }

    private func shouldKeepPreviewOpen() -> Bool {
        DockPreviewDockMouse.shouldKeepPreviewOpen(
            axIconRect: placementAnchorRect,
            activeDockItemToken: currentDockItemToken,
            hoveredDockItemToken: observer.currentHoveredDockItemToken(),
            panelFrame: panel.isVisible ? panel.panelFrame : nil,
            folderFrame: nil
        )
    }

    private func dismissVisiblePreviewIfNeeded(animated: Bool = false, reason: String = "pointer") {
        guard panel.isVisible else { return }
        dismissImmediately(animated: animated, reason: reason)
    }

    private func evaluatePendingShowCancellation() {
        if showWorkItem != nil, !shouldKeepPreviewOpen() {
            DockPreviewWorklog.log("show.cancelled", details: "left hover zone before delay elapsed")
            showWorkItem?.cancel()
            showWorkItem = nil
        }
    }

    private func logDismissSnapshot(trigger: String) {
        let keep = shouldKeepPreviewOpen()
        let onSurface = isPointerOnPreviewSurfaceOnly()
        let snapshot = "keep=\(keep) surface=\(onSurface) panel=\(panel.isVisible) active=\(currentDockItemToken ?? 0) hover=\(observer.currentHoveredDockItemToken() ?? 0)"
        guard snapshot != lastLoggedDismissSnapshot else { return }
        lastLoggedDismissSnapshot = snapshot
        DockPreviewWorklog.log("dismiss.state", fields: [
            "trigger": trigger,
            "keepOpen": keep,
            "onSurface": onSurface,
            "panelVisible": panel.isVisible,
            "activeToken": currentDockItemToken ?? 0,
            "hoverToken": observer.currentHoveredDockItemToken() ?? 0,
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
            evaluatePendingShowCancellation()
            if panel.isVisible, !settings.preventPreviewReentryDuringFadeOut, shouldKeepPreviewOpen() {
                panel.resetFadeState()
            }
        default:
            break
        }
    }

    private func handleContextMenuMouseDown(_ event: NSEvent) {
        guard isRunning else { return }
        guard isSecondaryClickEvent(event) else { return }

        let nearDock = DockPreviewDockPosition.isMouseInDockRegion(padding: 48)
        let previewActive = panel.isVisible || showWorkItem != nil
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
            placementAnchorRect = axIconRect
            anchoredAXIconRect = nil
            frozenDockItemToken = nil
            return
        }
        if frozenDockItemToken != dockItemToken {
            anchoredAXIconRect = DockPreviewPanelGeometry.frozenPlacementAnchor(axRect: axIconRect)
            frozenDockItemToken = dockItemToken
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
            var entries = await self.enumerator.windows(
                for: pid,
                settings: self.settings,
                bundleIdentifier: self.currentBundleIdentifier
            )
            entries = DockPreviewWindowFilter.filterByMonitor(entries, dockIconRect: iconRect, settings: self.settings)
            guard self.currentPID == pid else { return }
            if entries.isEmpty {
                if !self.settings.showWindowlessApps { return }
                self.showWindowlessApp(DockHoverTarget.AppHoverInfo(
                    pid: pid,
                    appName: self.currentAppName,
                    bundleIdentifier: self.currentBundleIdentifier,
                    iconRect: iconRect,
                    dockItemToken: self.currentDockItemToken ?? 0
                ))
                return
            }
            _ = self.cache.update(entries: entries, for: pid)
            let cached = self.cache.readCached(pid: pid)
            self.mergePanel(for: pid, entries: cached, reposition: false)
            self.captureThumbnailsIfNeeded(for: pid, entries: cached)
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
        entries = DockPreviewWindowFilter.filterBySpace(entries, settings: settings)
        entries = DockPreviewWindowFilter.filterByMonitor(entries, dockIconRect: iconRect, settings: settings)
        entries = DockPreviewWindowOrderStore.sort(
            entries,
            bundleIdentifier: currentBundleIdentifier,
            order: settings.sortOrder
        )
        if entries.isEmpty, settings.showWindowlessApps {
            showWindowlessApp(DockHoverTarget.AppHoverInfo(
                pid: pid, appName: currentAppName, bundleIdentifier: nil,
                iconRect: iconRect, dockItemToken: currentDockItemToken ?? 0
            ))
            scheduleWindowRefresh(for: pid, iconRect: iconRect, debounce: 0)
            return
        }
        if entries.isEmpty {
            // Wait for enumeration — avoid the broken single-row loading placeholder UI.
            scheduleWindowRefresh(for: pid, iconRect: iconRect, debounce: 0)
            return
        }
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
        guard !list.isEmpty || panelController.state.embeddedContent != .none else { return }
        if !panel.isVisible {
            dockAutoHide.preventHidingIfNeeded(settings: settings)
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
            enableLivePreview: settings.enableLivePreview,
            embeddedContent: panelController.state.embeddedContent
        )
        let placementKey = currentDockItemToken ?? 0
        panelController.present(
            presentation: presentation,
            placementKey: placementKey,
            reposition: reposition,
            onSelect: { [weak self] entry in
                Task { @MainActor in
                    DockPreviewWindowOrderStore.recordActivation(
                        bundleIdentifier: self?.currentBundleIdentifier,
                        windowTitle: entry.title
                    )
                    await self?.raiseService.raise(entry: entry, settings: self?.settings ?? .default)
                    self?.dismissImmediately(reason: "windowSelected")
                }
            }
        )
        if settings.enableLivePreview, mode == .fullPreview {
            let liveIDs = list.filter { !$0.title.isEmpty }.map(\.id)
            liveCapture.setActiveWindowIDs(liveIDs, settings: settings)
        }
    }

    private func captureThumbnailsIfNeeded(for pid: pid_t, entries: [DockPreviewWindowEntry]) {
        guard DockPreviewPermissionGate.currentMode(settings: settings) == .fullPreview else { return }
        for entry in entries where !entry.title.isEmpty {
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
                    self.mergePanel(
                        for: pid,
                        entries: self.cache.readCached(pid: pid),
                        reposition: false
                    )
                }
            }
        }
    }

    private func cancelThumbnailTasks(except keep: Set<CGWindowID> = []) {
        for (windowID, task) in thumbnailTasks where !keep.contains(windowID) {
            task.cancel()
            thumbnailTasks.removeValue(forKey: windowID)
        }
    }

    private func loadingPlaceholder(pid: pid_t) -> DockPreviewWindowEntry {
        DockPreviewWindowEntry(
            id: CGWindowID(UInt32(truncatingIfNeeded: pid) | 0x8000_0000),
            pid: pid,
            title: "",
            frame: .zero,
            thumbnail: nil,
            isMinimized: false,
            isOnScreen: false
        )
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
        panelController.state.embeddedContent = .none
        mergePanel(for: info.pid, entries: [placeholder], reposition: true)
    }

    private func presentFolderPreview(info: DockHoverTarget.FolderHoverInfo) {
        guard settings.enableFolderWidget else { return }
        dockAutoHide.preventHidingIfNeeded(settings: settings)
        let presentation = DockPreviewPanelPresentation(
            appIcon: nil,
            appName: info.title,
            entries: [],
            mode: .titlesOnly,
            anchorRect: placementAnchorRect,
            dockEdge: DockPreviewDockPosition.currentEdge(),
            enableLivePreview: false,
            embeddedContent: .folder(title: info.title, url: info.url)
        )
        panelController.present(
            presentation: presentation,
            placementKey: info.dockItemToken,
            reposition: true,
            onSelect: { _ in }
        )
    }
}
