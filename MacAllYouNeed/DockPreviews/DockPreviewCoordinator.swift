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
    let cache: DockPreviewWindowCache
    private var thumbnailCache: DockPreviewThumbnailCache
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
    private var thumbnailTasks: [CGWindowID: Task<Void, Never>] = [:]
    private var settingsObserver: NSObjectProtocol?
    private var mouseMonitors: [Any] = []
    private var terminateObserver: NSObjectProtocol?
    private var lastLoggedDismissSnapshot: String?

    var dockHoverObserver: DockHoverObserver { observer }
    var onAppHoverPID: ((pid_t?) -> Void)?

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
        panel.onDismissPreservePendingShow = { [weak self] in self?.dismissPreservingPendingShow() }
    }

    func reloadSettings(hub: DockHubSettings? = nil) {
        let loadedHub = hub ?? DockHubSettingsStore.load()
        hubSettings = loadedHub
        settings = loadedHub.previews
        DockPreviewWorklog.setEnabled(settings.enableWorklog)
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
        installPointerEventMonitors()
    }

    /// Warms the shared window cache for switcher-only mode (no dock hover observers).
    func startWindowCacheOnly() {
        guard !isRunning else { return }
        isRunning = true
        settings = hubSettings.previews
        DockPreviewLaunchSeeder.seed(
            cache: cache,
            enumerator: enumerator,
            settings: settings,
            maxApps: Int.max
        )
        cacheMaintainer.start()
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
        panel.resetFadeState()

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

            if panel.mouseIsWithinPreview,
               currentDockItemToken == info.dockItemToken,
               let displayedPID = currentPID,
               displayedPID != 0,
               info.pid != 0,
               displayedPID != info.pid {
                return
            }

            let switchingIcons = panel.isVisible && currentDockItemToken != info.dockItemToken

            if panel.isVisible,
               currentPID == info.pid,
               let shown = currentDockItemElement,
               let hovered = observer.getHoveredDockItemElement(),
               CFEqual(shown, hovered) {
                freezePlacementAnchor(axIconRect: info.iconRect, dockItemToken: info.dockItemToken)
                panel.resetFadeState()
                scheduleWindowRefresh(for: info.pid, iconRect: info.iconRect, debounce: 0.05)
                return
            }

            let cachedForPID = cache.readCached(pid: info.pid)
            cancelThumbnailTasks(except: Set(cachedForPID.map(\.id)))
            windowRefreshTask?.cancel()
            if switchingIcons {
                liveCapture.stopAll()
                panel.clearMouseInPreview()
                panel.resetFadeState()
            }
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

            if info.pid == 0 {
                if switchingIcons {
                    panelController.state.dismissalAnchorDockItem = currentDockItemElement
                }
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

            guard DockPreviewDockVisibility.isDockVisible() else {
                DockPreviewWorklog.log("panel.suppressed", fields: ["reason": "dockHidden"])
                return
            }

            if switchingIcons || (panel.isVisible && settings.skipDelayWhenPanelVisible) {
                if switchingIcons {
                    panelController.state.dismissalAnchorDockItem = currentDockItemElement
                }
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
        guard hovered.dockItemToken == currentDockItemToken else { return false }
        if let hoveredBundle = hovered.bundleIdentifier, !hoveredBundle.isEmpty {
            return hoveredBundle == bundleID
        }
        return hovered.pid == currentPID
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

    private func dismissPreservingPendingShow() {
        DockPreviewWorklog.log("dismiss.preservePendingShow", fields: [
            "pid": currentPID ?? 0,
            "token": currentDockItemToken ?? 0,
        ])
        windowRefreshTask?.cancel()
        windowRefreshTask = nil
        cancelThumbnailTasks()
        dockAutoHide.restoreIfNeeded()
        panel.dismiss(animated: false)
        liveCapture.scheduleStopAfterKeepAlive(settings: settings)
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
        lastLoggedDismissSnapshot = nil
        windowRefreshTask?.cancel()
        windowRefreshTask = nil
        cancelThumbnailTasks()
        dockAutoHide.restoreIfNeeded()
        panel.dismiss(animated: animated)
        liveCapture.scheduleStopAfterKeepAlive(settings: settings)
        panelController.state.dismissalAnchorDockItem = nil
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
                bundleIdentifier: self.currentBundleIdentifier,
                disableMinWindowSizeFilter: self.hubSettings.advanced.disableMinWindowSizeFilter
            )
            entries = DockPreviewWindowFilter.filter(entries, settings: self.settings)
            entries = DockPreviewWindowFilter.filterBySpace(entries, settings: self.settings)
            entries = DockPreviewWindowFilter.filterByMonitor(entries, dockIconRect: iconRect, settings: self.settings)
            entries = DockPreviewWindowFilter.applyHubFilters(
                entries,
                hub: self.hubSettings,
                bundleIdentifier: self.currentBundleIdentifier,
                appName: self.currentAppName
            )
            if self.settings.ignoreSingleWindowApps, entries.count <= 1 {
                entries = []
            }
            guard self.currentPID == pid else { return }
            if pid != 0,
               let bundleID = self.currentBundleIdentifier,
               !self.isExpectedAppStillHovered(bundleID: bundleID) {
                return
            }
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
            _ = self.cache.update(entries: entries, for: pid)
            let cached = self.cache.readCached(pid: pid)
            self.mergePanel(for: pid, entries: cached, reposition: false)
            self.captureThumbnailsIfNeeded(for: pid, entries: cached)
        }
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
            entries = []
        }
        if entries.isEmpty, settings.showWindowlessApps {
            showWindowlessApp(DockHoverTarget.AppHoverInfo(
                pid: pid, appName: currentAppName, bundleIdentifier: currentBundleIdentifier,
                iconRect: iconRect, dockItemToken: currentDockItemToken ?? 0
            ))
            scheduleWindowRefresh(for: pid, iconRect: iconRect, debounce: 0)
            return
        }
        if entries.isEmpty {
            if forceShellUpdate, panel.isVisible {
                dismissImmediately(reason: "iconSwitchEmpty", cancelPendingShow: false)
            }
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
        let list = entries ?? cache.readCached(pid: pid)
        guard !list.isEmpty || panelController.state.embeddedContent != .none || allowEmpty else { return }
        if !panel.isVisible {
            panelController.state.dismissalAnchorDockItem = currentDockItemElement
        }
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
