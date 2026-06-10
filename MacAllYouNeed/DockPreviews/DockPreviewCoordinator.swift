import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import Platform

@MainActor
@Observable
final class DockPreviewCoordinator {
    private let observer: DockHoverObserver
    private let enumerator: any WindowEnumerating
    private let thumbnailService: any ThumbnailCapturing
    let diskStore: DockPreviewThumbnailDiskStore
    let cache: DockPreviewWindowCache
    let capturePipeline: DockPreviewWindowCapturePipeline
    private let visibleThumbnailCache: DockPreviewVisibleThumbnailCache
    private let dockWorker: DockPreviewWorker
    private let refreshScope = DockPreviewRefreshScope()
    private let axCacheObservers = DockPreviewWindowAXCacheObservers()
    private let raiseService: DockPreviewRaiseService
    private let panelController: DockPreviewPanelController
    private var panel: DockPreviewPanel { panelController.panel }
    private let liveCapture = DockPreviewLiveCaptureManager.shared
    private let dockAutoHide = DockPreviewDockAutoHideManager()
    private let cacheMaintainer: DockPreviewWindowCacheMaintainer

    private var settings = DockHubSettingsStore.loadPreviews()
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
    private var currentDockItemElement: AXUIElement?
    private var isRunning = false
    private var showWorkItem: DispatchWorkItem?
    private var showWorkToken: UInt = 0
    private var windowRefreshTask: Task<Void, Never>?
    private var settingsObserver: NSObjectProtocol?
    private var clickMonitors: [Any] = []
    private var moveMonitors: [Any] = []
    private var coalescedPointerWorkItem: DispatchWorkItem?
    private var lastDockSelectionPollTime: CFAbsoluteTime = 0
    private var terminateObserver: NSObjectProtocol?
    private var lastLoggedDismissSnapshot: String?
    private var dockPrewarmTask: Task<Void, Never>?
    /// Bumps on each `mergePanel` so stale async disk hydrates cannot repaint the wrong hover.
    private var mergeHydrationGeneration: UInt64 = 0

    var dockHoverObserver: DockHoverObserver { observer }
    var onAppHoverPID: ((pid_t?) -> Void)?

    init(
        panelController: DockPreviewPanelController,
        coordinator axCoordinator: AXObserverCoordinator,
        dockWorker: DockPreviewWorker
    ) {
        self.panelController = panelController
        self.dockWorker = dockWorker
        observer = DockHoverObserver(coordinator: axCoordinator)
        enumerator = SystemWindowEnumerator()
        thumbnailService = DockPreviewThumbnailService()
        diskStore = DockPreviewThumbnailDiskStore()
        cache = DockPreviewWindowCache(diskStore: diskStore)
        visibleThumbnailCache = DockPreviewVisibleThumbnailCache(diskStore: diskStore)
        capturePipeline = DockPreviewWindowCapturePipeline(
            cache: cache,
            diskStore: diskStore,
            enumerator: enumerator,
            thumbnailService: thumbnailService,
            dockWorker: dockWorker
        )
        cacheMaintainer = DockPreviewWindowCacheMaintainer(cache: cache, pipeline: capturePipeline)
        raiseService = DockPreviewRaiseService(enumerator: enumerator)
        panel.onDismissRequest = { [weak self] in self?.handleInactivityDismiss() }
        panel.onDismissPreservePendingShow = { [weak self] in self?.dismissPreservingPendingShow() }
    }

    func reloadSettings(hub: DockHubSettings? = nil) {
        let loadedHub = hub ?? DockHubSettingsStore.load()
        hubSettings = loadedHub
        settings = loadedHub.previews
        DockPreviewWorklog.setEnabled(settings.enableWorklog)
        panelController.reloadSettings(loadedHub)
        capturePipeline.reloadSettings(hub: loadedHub)
        cacheMaintainer.reloadSettings(hub: loadedHub)
        observer.settings = { [weak self] in self?.settings ?? .default }
        if panel.isVisible, let pid = currentPID, case .app = currentHover {
            mergePanel(for: pid, reposition: false)
        } else if !settings.enableLivePreview {
            liveCapture.stopAll()
        }
    }

    func start() {
        guard !isRunning else { return }
        guard AXIsProcessTrusted() else { return }
        isRunning = true
        reloadSettings()
        DockPreviewWorklog.log("runtime.start", fields: [
            "axTrusted": AXIsProcessTrusted(),
            "worklog": settings.enableWorklog,
            "thumbRoot": diskStore.rootPath,
            "cacheLifespanSec": capturePipeline.cacheLifespan,
        ])
        if settings.enableWorklog {
            Task { await diskStore.logInventory() }
        }
        observer.settings = { [weak self] in self?.settings ?? .default }
        observer.onHoverBegan = { [weak self] target in
            self?.handleHoverBegan(target)
        }
        observer.onHoverEnded = { [weak self] in
            self?.handleHoverEnded()
        }
        observer.shouldSuppressSelectionPolling = { [weak self] in
            guard let self else { return false }
            if DockPreviewDockPosition.isMouseInDockRegion(padding: 48) {
                return false
            }
            return self.shouldKeepPreviewOpen()
        }
        DockHoverObserver.lastHoveredTokenProvider = { [weak self] in
            self?.observer.currentHoveredDockItemToken()
        }
        observer.onDockProximity = { [weak self] in
            self?.handleDockProximity()
        }
        observer.start()
        DockPreviewLaunchSeeder.seed(pipeline: capturePipeline)
        cacheMaintainer.start(refreshScope: refreshScope)
        axCacheObservers.onSpaceWillChange = { [weak self] in
            self?.dismissDockPreviewForWorkspaceChange(reason: "spaceChange")
        }
        axCacheObservers.start(pipeline: capturePipeline, refreshScope: refreshScope)
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
        installClickEventMonitors()
        syncPointerMoveMonitoring()
    }

    /// Warms the shared window cache for switcher-only mode (no dock hover observers).
    func startWindowCacheOnly() {
        guard !isRunning else { return }
        isRunning = true
        settings = hubSettings.previews
        DockPreviewLaunchSeeder.seed(pipeline: capturePipeline)
        cacheMaintainer.start(refreshScope: refreshScope)
        axCacheObservers.start(pipeline: capturePipeline, refreshScope: refreshScope)
    }

    func stop() {
        DockPreviewWorklog.log("runtime.stop")
        isRunning = false
        cacheMaintainer.stop()
        axCacheObservers.stop()
        if let terminateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminateObserver)
        }
        terminateObserver = nil
        dockAutoHide.restoreIfNeeded()
        removePointerEventMonitors()
        coalescedPointerWorkItem?.cancel()
        coalescedPointerWorkItem = nil
        clearSwitcherSession()
        showWorkItem?.cancel()
        showWorkItem = nil
        windowRefreshTask?.cancel()
        windowRefreshTask = nil
        dockPrewarmTask?.cancel()
        dockPrewarmTask = nil
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        settingsObserver = nil
        observer.stop()
        panel.dismiss(animated: false)
        liveCapture.stopAll()
        visibleThumbnailCache.evictAll()
        cache.clearAll()
        currentPID = nil
        currentBundleIdentifier = nil
        currentHover = .none
    }

    func refreshPermissions() {
        if panel.isVisible, let pid = currentPID {
            mergePanel(for: pid, reposition: false)
        }
    }

    func hydrateForDisplay(_ entries: [DockPreviewWindowEntry]) -> [DockPreviewWindowEntry] {
        visibleThumbnailCache.hydrate(entries)
    }

    func hydrateForDisplayAsync(_ entries: [DockPreviewWindowEntry]) async -> [DockPreviewWindowEntry] {
        let prefetched = await dockWorker.hydrateEntries(entries, diskStore: diskStore)
        return visibleThumbnailCache.hydrate(prefetched)
    }

    func evictVisibleThumbnails() {
        visibleThumbnailCache.evictAll()
    }

    /// Keeps AX window observers and `refreshApp` scoped to switcher-visible PIDs while Option+Tab is open.
    func noteSwitcherSession(pids: [pid_t]) {
        refreshScope.noteSwitcherSession(pids: pids)
        guard isRunning else { return }
        axCacheObservers.reconcileObservers()
    }

    func clearSwitcherSession() {
        refreshScope.clearSwitcherSession()
        guard isRunning else { return }
        axCacheObservers.reconcileObservers()
    }

    /// Refreshes warmed window caches after sleep/wake (AX recovery is owned by `DockHoverObserver`).
    func refreshCachesAfterWake() {
        guard isRunning else { return }
        cacheMaintainer.refreshAllRunningApps()
    }

    /// DockDoor `appDidActivate` / `activeSpaceDidChange` — dismiss dock hover panel, keep cache warm.
    func dismissDockPreviewForWorkspaceChange(reason: String) {
        guard panel.isVisible else { return }
        switch panelController.state.mode {
        case .windowSwitcher, .cmdTab:
            return
        case .dockHover:
            dismissImmediately(reason: reason, cancelPendingShow: false)
        }
    }

    func handleApplicationActivated() {
        dismissDockPreviewForWorkspaceChange(reason: "appActivated")
        refreshScope.noteDockProximity()
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.activationPolicy == .regular,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }
        Task { @MainActor [weak self] in
            await self?.capturePipeline.refreshAppIfNeeded(
                pid: app.processIdentifier,
                bundleIdentifier: app.bundleIdentifier
            )
        }
    }

    /// Starts background warm when the pointer enters the dock band after a long idle spell.
    private func handleDockProximity() {
        refreshScope.noteDockProximity()
        guard refreshScope.isIdle else { return }
        dockPrewarmTask?.cancel()
        dockPrewarmTask = Task { @MainActor [weak self] in
            guard let self else { return }
            DockPreviewWorklog.log("warm.dockProximity", fields: [:])
            await self.capturePipeline.warmAllRunningApps(throttle: true)
            self.dockPrewarmTask = nil
        }
    }

    private func handleHoverBegan(_ target: DockHoverTarget) {
        showWorkItem?.cancel()
        lastLoggedDismissSnapshot = nil
        panel.resetFadeState()

        switch target {
        case .folder(let info):
            DockPreviewWorklog.log("hover.folder", fields: [
                "title": info.title,
                "token": info.dockItemToken,
            ])
            windowRefreshTask?.cancel()
            liveCapture.stopAll()
            currentHover = target
            currentPID = 0
            currentDockItemToken = info.dockItemToken
            currentDockItemElement = observer.getHoveredDockItemElement()
            panelController.state.dockItemToken = info.dockItemToken
            freezePlacementAnchor(axIconRect: info.iconRect, dockItemToken: info.dockItemToken)
            panelController.state.embeddedContent = .folder(title: info.title, url: info.url)
            panelController.state.appearance = DockPreviewAppearanceContext.resolve(
                mode: .dockHover,
                settings: settings,
                hubAppearance: hubSettings.appearance
            )
            presentFolderPreview(info: info)
        case .app(let info):
            DockPreviewWorklog.log("hover.app", fields: [
                "app": info.appName,
                "pid": info.pid,
                "token": info.dockItemToken,
            ])
            if DockPreviewWindowFilter.isAppFiltered(
                bundleIdentifier: info.bundleIdentifier,
                appName: info.appName,
                filters: hubSettings.filters
            ) {
                onAppHoverPID?(nil)
                return
            }
            onAppHoverPID?(info.pid != 0 ? info.pid : nil)
            panelController.state.bundleIdentifier = info.bundleIdentifier
            panelController.state.embeddedContent = DockPreviewEmbedRouting.embeddedContent(
                bundleIdentifier: info.bundleIdentifier,
                appName: info.appName,
                widgets: hubSettings.widgets,
                filters: hubSettings.filters
            )
            panelController.state.appearance = DockPreviewAppearanceContext.resolve(
                mode: .dockHover,
                settings: settings,
                hubAppearance: hubSettings.appearance
            )

            if DockPreviewDockMouse.shouldIgnoreDockHoverChange(
                panelVisible: panel.isVisible,
                mouseIsWithinPreview: panel.mouseIsWithinPreview,
                panelFrame: panel.isVisible ? panel.panelFrame : nil,
                folderFrame: nil,
                currentToken: currentDockItemToken,
                newToken: info.dockItemToken,
                currentPID: currentPID,
                newPID: info.pid,
                currentBundleID: currentBundleIdentifier,
                newBundleID: info.bundleIdentifier
            ) {
                DockPreviewWorklog.log("hover.ignoredOnPreview", fields: [
                    "app": info.appName,
                    "pid": info.pid,
                    "activeToken": currentDockItemToken ?? 0,
                    "hoverToken": info.dockItemToken,
                ])
                return
            }

            let switchingIcons = panel.isVisible && currentDockItemToken != info.dockItemToken
            let previouslyDisplayedPID = currentPID
            let crossAppSwitch = DockPreviewDockMouse.isCrossAppDockSwitch(
                displayedPID: previouslyDisplayedPID,
                targetPID: info.pid,
                displayedBundleID: currentBundleIdentifier,
                targetBundleID: info.bundleIdentifier
            )
            let pointerInDockRegion = DockPreviewDockPosition.isMouseInDockRegion(padding: 48)

            if DockPreviewDockMouse.shouldAbsorbSameAppDockTokenChurn(
                panelVisible: panel.isVisible,
                mouseIsWithinPreview: panel.mouseIsWithinPreview,
                pointerInDockRegion: pointerInDockRegion,
                currentPID: currentPID,
                newPID: info.pid,
                currentToken: currentDockItemToken,
                newToken: info.dockItemToken
            ) {
                currentDockItemToken = info.dockItemToken
                currentDockItemElement = observer.getHoveredDockItemElement()
                freezePlacementAnchor(axIconRect: info.iconRect, dockItemToken: info.dockItemToken)
                DockPreviewWorklog.log("hover.sameAppTokenAbsorbed", fields: [
                    "app": info.appName,
                    "pid": info.pid,
                    "token": info.dockItemToken,
                ])
                return
            }

            if panel.isVisible,
               let shown = currentDockItemElement,
               let hovered = observer.getHoveredDockItemElement(),
               CFEqual(shown, hovered) {
                freezePlacementAnchor(axIconRect: info.iconRect, dockItemToken: info.dockItemToken)
                if panel.mouseIsWithinPreview || pointerInDockRegion {
                    panel.resetFadeState()
                }
                if currentPID == info.pid, info.pid != 0 {
                    scheduleWindowRefresh(for: info.pid, iconRect: info.iconRect, debounce: 0.05)
                }
                return
            }

            windowRefreshTask?.cancel()
            if switchingIcons {
                liveCapture.stopAll()
                panel.clearMouseInPreview()
                panel.resetFadeState()
            }

            let wantsInstantPresent = switchingIcons
                || (panel.isVisible && settings.skipDelayWhenPanelVisible)
            if wantsInstantPresent, info.pid != 0 {
                let hovered = observer.currentAppHoverInfo()
                guard DockPreviewDockMouse.shouldAllowInstantDockSwitch(
                    mouseIsWithinPreview: panel.mouseIsWithinPreview,
                    onPreviewSurface: isPointerOnPreviewSurfaceOnly(),
                    pointerInDockRegion: pointerInDockRegion,
                    targetBundleID: info.bundleIdentifier,
                    targetPID: info.pid,
                    hoveredBundleID: hovered?.bundleIdentifier,
                    hoveredPID: hovered?.pid ?? 0,
                    displayedPID: previouslyDisplayedPID,
                    crossAppSwitch: crossAppSwitch
                ) else {
                    DockPreviewWorklog.log("hover.blockedInstantSwitch", fields: [
                        "app": info.appName,
                        "pid": info.pid,
                        "displayedPID": previouslyDisplayedPID ?? 0,
                        "hoveredPID": hovered?.pid ?? 0,
                        "crossApp": crossAppSwitch,
                    ])
                    return
                }
            }

            commitAppHoverState(target: target, info: info)

            if info.pid == 0 {
                if settings.showWindowlessApps {
                    let delay = hoverDelayForPresent(switchingIcons: switchingIcons)
                    scheduleShow(delay: delay, dockItemToken: info.dockItemToken, expectedPID: 0) { [weak self] in
                        self?.showWindowlessApp(info)
                    }
                } else if panel.isVisible {
                    panel.clearMouseInPreview()
                    dismissImmediately(reason: "notRunningApp", cancelPendingShow: true)
                }
                return
            }

            if let suppression = DockPreviewDockVisibility.suppressionDetail() {
                DockPreviewWorklog.log("panel.suppressed", fields: [
                    "reason": "dockHidden",
                    "detail": suppression,
                ])
                return
            }

            if wantsInstantPresent {
                presentCachedThenRefresh(
                    pid: info.pid,
                    iconRect: info.iconRect,
                    reposition: true,
                    forceShellUpdate: switchingIcons
                )
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
        onAppHoverPID?(nil)
        refreshScope.noteHoverEnded()
        axCacheObservers.reconcileObservers()
        logDismissSnapshot(trigger: "hoverEnded")
        // DockDoor: AX selection clearing does not hide the panel — inactivity fade owns dismissal.
        if isPointerOnPreviewSurfaceOnly() {
            DockPreviewWorklog.log("hoverEnded.keepOnSurface")
            return
        }
        if shouldKeepPreviewOpen() {
            return
        }
        showWorkItem?.cancel()
        showWorkItem = nil
    }

    private func isExpectedAppStillHovered(bundleID: String) -> Bool {
        guard let hovered = observer.currentAppHoverInfo() else { return false }
        if let hoveredBundle = hovered.bundleIdentifier, !hoveredBundle.isEmpty {
            return hoveredBundle == bundleID
        }
        guard let currentPID, currentPID != 0 else { return false }
        return hovered.pid == currentPID
    }

    private func commitAppHoverState(target: DockHoverTarget, info: DockHoverTarget.AppHoverInfo) {
        currentHover = target
        currentPID = info.pid
        currentBundleIdentifier = info.bundleIdentifier
        currentAppName = info.appName
        currentDockItemToken = info.dockItemToken
        currentDockItemElement = observer.getHoveredDockItemElement()
        panelController.state.dockItemToken = info.dockItemToken
        currentAppIcon = info.pid != 0
            ? NSWorkspace.shared.runningApplications.first { $0.processIdentifier == info.pid }?.icon
            : nil
        refreshScope.noteHover(pid: info.pid)
        axCacheObservers.ensureObserver(for: info.pid)
        axCacheObservers.reconcileObservers()
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
        syncPointerMoveMonitoring()
        if delay <= 0 {
            work.perform()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func dismissPreservingPendingShow() {
        DockPreviewWorklog.log("dismiss.preservePendingShow", fields: [
            "pid": currentPID ?? 0,
            "token": currentDockItemToken ?? 0,
        ])
        windowRefreshTask?.cancel()
        windowRefreshTask = nil
        dockAutoHide.restoreIfNeeded()
        panel.hideForDockIconTransition()
        liveCapture.scheduleStopAfterKeepAlive(hub: hubSettings)
        panelController.state.dismissalAnchorDockItem = nil
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
        mergeHydrationGeneration &+= 1
        lastLoggedDismissSnapshot = nil
        windowRefreshTask?.cancel()
        windowRefreshTask = nil
        dockAutoHide.restoreIfNeeded()
        DockPreviewTooltipOverlay.shared.dismiss()
        panel.dismiss(animated: animated)
        liveCapture.scheduleStopAfterKeepAlive(hub: hubSettings)
        visibleThumbnailCache.evictAll()
        panelController.state.dismissalAnchorDockItem = nil
        currentPID = nil
        currentBundleIdentifier = nil
        currentHover = .none
        currentDockItemToken = nil
        placementAnchorRect = .zero
        anchoredAXIconRect = nil
        frozenDockItemToken = nil
        refreshScope.setPanelVisible(false)
        syncPointerMoveMonitoring()
    }

    private func handleInactivityDismiss() {
        guard panel.isVisible else { return }
        if shouldKeepPreviewOpen() {
            if !settings.preventPreviewReentryDuringFadeOut {
                panel.resetFadeState()
            }
            return
        }
        dismissImmediately(animated: false, reason: "inactivity")
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
            folderFrame: nil
        )
    }

    private func shouldKeepPreviewOpen() -> Bool {
        DockPreviewDockMouse.shouldKeepPreviewOpen(
            mouseIsWithinPreview: panel.mouseIsWithinPreview,
            panelFrame: panel.isVisible ? panel.panelFrame : nil,
            folderFrame: nil
        )
    }

    private func evaluatePendingShowCancellation() {
        if showWorkItem != nil, !shouldKeepPreviewOpen() {
            DockPreviewWorklog.log("show.cancelled", details: "left hover zone before delay elapsed")
            showWorkItem?.cancel()
            showWorkItem = nil
            syncPointerMoveMonitoring()
        }
    }

    private func logDismissSnapshot(trigger: String) {
        guard settings.enableWorklog else { return }
        let keep = shouldKeepPreviewOpen()
        let onSurface = isPointerOnPreviewSurfaceOnly()
        let hoverToken = observer.currentHoveredDockItemToken() ?? 0
        let snapshot = "keep=\(keep) surface=\(onSurface) panel=\(panel.isVisible) active=\(currentDockItemToken ?? 0) hover=\(hoverToken)"
        guard snapshot != lastLoggedDismissSnapshot else { return }
        lastLoggedDismissSnapshot = snapshot
        DockPreviewWorklog.log("dismiss.state", fields: [
            "trigger": trigger,
            "keepOpen": keep,
            "onSurface": onSurface,
            "panelVisible": panel.isVisible,
            "activeToken": currentDockItemToken ?? 0,
            "hoverToken": hoverToken,
        ])
    }

    private func installClickEventMonitors() {
        removePointerEventMonitors()
        let clickMask: NSEvent.EventTypeMask = [.rightMouseDown, .otherMouseDown, .leftMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clickMask) { [weak self] event in
            Task { @MainActor in self?.handlePointerEvent(event) }
        } {
            clickMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: clickMask) { [weak self] event in
            Task { @MainActor in self?.handlePointerEvent(event) }
            return event
        } {
            clickMonitors.append(local)
        }
    }

    private func syncPointerMoveMonitoring() {
        refreshScope.setPanelVisible(panel.isVisible)
        refreshScope.setPendingShow(showWorkItem != nil)
        let needsMove = panel.isVisible || showWorkItem != nil
        if needsMove, moveMonitors.isEmpty {
            let moveMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
            if let global = NSEvent.addGlobalMonitorForEvents(matching: moveMask) { [weak self] event in
                Task { @MainActor in self?.handlePointerEvent(event) }
            } {
                moveMonitors.append(global)
            }
            if let local = NSEvent.addLocalMonitorForEvents(matching: moveMask) { [weak self] event in
                Task { @MainActor in self?.handlePointerEvent(event) }
                return event
            } {
                moveMonitors.append(local)
            }
        } else if !needsMove, !moveMonitors.isEmpty {
            coalescedPointerWorkItem?.cancel()
            coalescedPointerWorkItem = nil
            for monitor in moveMonitors {
                NSEvent.removeMonitor(monitor)
            }
            moveMonitors = []
        }
    }

    private func removePointerEventMonitors() {
        coalescedPointerWorkItem?.cancel()
        coalescedPointerWorkItem = nil
        for monitor in clickMonitors + moveMonitors {
            NSEvent.removeMonitor(monitor)
        }
        clickMonitors = []
        moveMonitors = []
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
            scheduleCoalescedPointerEvaluation()
        default:
            break
        }
    }

    private func scheduleCoalescedPointerEvaluation() {
        coalescedPointerWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.coalescedPointerWorkItem = nil
            self.evaluatePendingShowCancellation()
            if self.panel.isVisible {
                let now = CFAbsoluteTimeGetCurrent()
                if now - self.lastDockSelectionPollTime >= 0.15 {
                    self.lastDockSelectionPollTime = now
                    self.observer.pollDockSelectionIfPointerInDockRegion()
                }
                if !self.settings.preventPreviewReentryDuringFadeOut,
                   self.shouldKeepPreviewOpen() {
                    self.panel.resetFadeState()
                }
            }
        }
        coalescedPointerWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60.0, execute: work)
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
            if pid != 0,
               let bundleID = self.currentBundleIdentifier,
               !self.isExpectedAppStillHovered(bundleID: bundleID) {
                return
            }
            await self.capturePipeline.refreshAppIfNeeded(
                pid: pid,
                bundleIdentifier: self.currentBundleIdentifier
            )
            guard self.currentPID == pid else { return }
            let entries = self.filteredCachedEntries(pid: pid, iconRect: iconRect)
            if entries.isEmpty {
                if self.settings.showWindowlessApps {
                    self.showWindowlessApp(DockHoverTarget.AppHoverInfo(
                        pid: pid,
                        appName: self.currentAppName,
                        bundleIdentifier: self.currentBundleIdentifier,
                        iconRect: iconRect,
                        dockItemToken: self.currentDockItemToken ?? 0
                    ))
                } else if self.panel.isVisible, self.currentPID == pid {
                    self.dismissImmediately(reason: "noWindows", cancelPendingShow: false)
                }
                return
            }
            if !self.panel.isVisible {
                self.dockAutoHide.preventHidingIfNeeded(settings: self.settings)
            }
            self.mergePanel(for: pid, entries: entries, reposition: false)
        }
    }

    private func filteredCachedEntries(pid: pid_t, iconRect: CGRect) -> [DockPreviewWindowEntry] {
        var entries = cache.readCached(pid: pid)
        entries = DockPreviewWindowFilter.filter(entries, settings: settings)
        entries = DockPreviewWindowFilter.filterBySpace(entries, settings: settings)
        entries = DockPreviewWindowFilter.filterByMonitor(entries, dockIconRect: iconRect, settings: settings)
        entries = DockPreviewWindowFilter.applyHubFilters(
            entries,
            hub: hubSettings,
            bundleIdentifier: currentBundleIdentifier,
            appName: currentAppName
        )
        entries = DockPreviewWindowOrderStore.sort(
            entries,
            bundleIdentifier: currentBundleIdentifier,
            order: settings.sortOrder
        )
        if settings.ignoreSingleWindowApps, entries.count <= 1 {
            return []
        }
        return entries
    }

    private func presentCachedThenRefresh(
        pid: pid_t,
        iconRect: CGRect,
        reposition: Bool,
        forceShellUpdate: Bool = false
    ) {
        guard case .app = currentHover, currentPID == pid else { return }
        freezePlacementAnchor(axIconRect: iconRect, dockItemToken: currentDockItemToken ?? 0)
        DockPreviewWorklog.log("panel.present", fields: [
            "pid": pid,
            "reposition": reposition,
            "cached": cache.readCached(pid: pid).count,
            "forceShell": forceShellUpdate,
        ])
        var entries = filteredCachedEntries(pid: pid, iconRect: iconRect)
        if entries.isEmpty, settings.showWindowlessApps {
            showWindowlessApp(DockHoverTarget.AppHoverInfo(
                pid: pid, appName: currentAppName, bundleIdentifier: currentBundleIdentifier,
                iconRect: iconRect, dockItemToken: currentDockItemToken ?? 0
            ))
            scheduleWindowRefresh(for: pid, iconRect: iconRect, debounce: 0)
            return
        }
        if entries.isEmpty {
            scheduleWindowRefresh(for: pid, iconRect: iconRect, debounce: 0)
            return
        }
        mergePanel(for: pid, entries: entries, reposition: reposition)
        captureThumbnailsIfNeeded(for: pid, entries: entries)
    }

    private func mergePanel(
        for pid: pid_t,
        entries: [DockPreviewWindowEntry]? = nil,
        reposition: Bool,
        allowEmpty: Bool = false
    ) {
        guard currentPID == pid, case .app = currentHover else { return }
        let raw = entries ?? cache.readCached(pid: pid)
        mergeHydrationGeneration &+= 1
        let generation = mergeHydrationGeneration

        // Paint immediately from LRU / in-memory thumbnails so hover does not wait on disk I/O.
        let quickList = visibleThumbnailCache.hydrate(raw)
        applyMergePanel(
            for: pid,
            list: quickList,
            reposition: reposition,
            allowEmpty: allowEmpty
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard generation == self.mergeHydrationGeneration else { return }
            guard self.currentPID == pid, case .app = self.currentHover else { return }
            let hydrated = await self.hydrateForDisplayAsync(raw)
            guard generation == self.mergeHydrationGeneration else { return }
            guard self.currentPID == pid, case .app = self.currentHover else { return }
            guard Self.entriesNeedThumbnailRefresh(quickList, hydrated) else { return }
            self.applyMergePanel(
                for: pid,
                list: hydrated,
                reposition: false,
                allowEmpty: allowEmpty
            )
        }
    }

    private static func entriesNeedThumbnailRefresh(
        _ before: [DockPreviewWindowEntry],
        _ after: [DockPreviewWindowEntry]
    ) -> Bool {
        guard before.count == after.count else { return true }
        for (lhs, rhs) in zip(before, after) {
            if lhs.id != rhs.id { return true }
            let hadThumb = lhs.thumbnail != nil
            let hasThumb = rhs.thumbnail != nil
            if hadThumb != hasThumb { return true }
        }
        return false
    }

    private func applyMergePanel(
        for pid: pid_t,
        list: [DockPreviewWindowEntry],
        reposition: Bool,
        allowEmpty: Bool
    ) {
        guard !list.isEmpty || panelController.state.embeddedContent != .none || allowEmpty else { return }
        if !panel.isVisible {
            panelController.state.dismissalAnchorDockItem = currentDockItemElement
            refreshScope.setPanelVisible(true)
            syncPointerMoveMonitoring()
        }
        if !panel.isVisible {
            dockAutoHide.preventHidingIfNeeded(settings: settings)
            DockPreviewWorklog.log("panel.show", fields: [
                "pid": pid,
                "windows": list.count,
                "mode": String(describing: DockPreviewPermissionGate.currentMode(settings: settings, hub: hubSettings)),
            ])
        }
        let mode = DockPreviewPermissionGate.currentMode(settings: settings, hub: hubSettings)
        let liveEnabled = settings.enableLivePreview && hubSettings.master.enableDockPreviews
        let anchor = settings.anchorToDockIcon ? placementAnchorRect : .zero
        let presentation = DockPreviewPanelPresentation(
            appIcon: currentAppIcon,
            appName: currentAppName,
            entries: list,
            mode: mode,
            anchorRect: anchor,
            dockEdge: DockPreviewDockPosition.currentEdge(),
            enableLivePreview: liveEnabled,
            embeddedContent: panelController.state.embeddedContent
        )
        let placementKey = currentDockItemToken ?? 0
        if settings.overlayDockTooltip,
           presentation.dockEdge == .bottom,
           anchor != .zero
        {
            let screen = DockPreviewDockCoordinates.screen(containingAXPoint: anchor.origin)
            DockPreviewTooltipOverlay.shared.show(iconRect: anchor, screen: screen)
        } else {
            DockPreviewTooltipOverlay.shared.dismiss()
        }
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
        if liveEnabled, mode == .fullPreview {
            let liveIDs = list.filter { !$0.title.isEmpty }.map(\.id)
            liveCapture.setActiveWindowIDs(
                liveIDs,
                hub: hubSettings,
                context: .dockHover,
                enabled: true
            )
        } else {
            liveCapture.stopAll()
        }
    }

    private func captureThumbnailsIfNeeded(for pid: pid_t, entries: [DockPreviewWindowEntry]) {
        guard DockPreviewPermissionGate.shouldCaptureWindowImages(hub: hubSettings) else { return }
        guard !capturePipeline.isDisplayCacheFresh(pid: pid) else { return }
        _ = entries
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.capturePipeline.attachThumbnails(pid: pid)
            if !self.settings.enableLivePreview {
                await self.capturePipeline.seedLiveSnapshotsForMissingThumbnails(pid: pid, maxCaptures: 3)
            }
            guard self.currentPID == pid else { return }
            self.mergePanel(for: pid, reposition: false)
        }
    }

    private func showWindowlessApp(_ info: DockHoverTarget.AppHoverInfo) {
        freezePlacementAnchor(axIconRect: info.iconRect, dockItemToken: info.dockItemToken)
        if hubSettings.advanced.openNewWindowForWindowlessApps,
           let app = NSRunningApplication(processIdentifier: info.pid)
        {
            app.activate()
            postNewWindowShortcut()
        }
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
        guard hubSettings.widgets.enableDockItemWidgets, settings.enableFolderWidget else { return }
        let folderURL = DockFolderWidgetBookmarkStore.accessibleURL(for: info.url) ?? info.url
        dockAutoHide.preventHidingIfNeeded(settings: settings)
        refreshScope.setPanelVisible(true)
        syncPointerMoveMonitoring()
        let presentation = DockPreviewPanelPresentation(
            appIcon: nil,
            appName: info.title,
            entries: [],
            mode: .titlesOnly,
            anchorRect: placementAnchorRect,
            dockEdge: DockPreviewDockPosition.currentEdge(),
            enableLivePreview: false,
            embeddedContent: .folder(title: info.title, url: folderURL)
        )
        panelController.present(
            presentation: presentation,
            placementKey: info.dockItemToken,
            reposition: true,
            onSelect: { _ in }
        )
    }

    private func postNewWindowShortcut() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_N), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_N), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

}
