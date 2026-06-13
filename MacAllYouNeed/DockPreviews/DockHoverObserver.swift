import AppKit
import ApplicationServices
import Foundation
import Platform

@MainActor
final class DockHoverObserver {
    private let coordinator: AXObserverCoordinator
    private var dockPID: pid_t?
    private var dockAXList: AXUIElement?
    private var healthCheckTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var wakeRecoveryTask: Task<Void, Never>?
    private var lastHoverToken: UInt?
    private var lastAppHoverSignature: String?
    private let mainBundleID = Bundle.main.bundleIdentifier

    var onHoverBegan: ((DockHoverTarget) -> Void)?
    var onHoverEnded: (() -> Void)?
    /// Called after wake recovery rebuilds the Dock AX subscription.
    var onSystemWakeRecovery: (() -> Void)?
    /// Called on each 5s health check (event tap recovery, cache refresh, etc.).
    var onPeriodicHealthCheck: (() -> Void)?
    /// Called when the pointer is in the dock band (health check / selection poll).
    var onDockProximity: (() -> Void)?
    /// When true, skip health-check polling of dock selection (cursor on preview panel).
    var shouldSuppressSelectionPolling: (() -> Bool)?
    var settings: () -> DockPreviewSettings = { DockHubSettingsStore.loadPreviews() }

    init(coordinator: AXObserverCoordinator) {
        self.coordinator = coordinator
    }

    func start() {
        Self.activeObserver = self
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)
        resetSubscription()
        startHealthCheck()
        installWakeObserverIfNeeded()
    }

    func stop() {
        if Self.activeObserver === self {
            Self.activeObserver = nil
        }
        wakeRecoveryTask?.cancel()
        wakeRecoveryTask = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        healthCheckTask?.cancel()
        healthCheckTask = nil
        coordinator.stop()
        dockPID = nil
        dockAXList = nil
        lastHoverToken = nil
    }

    /// Stable token for the dock item last reported via AX (do not re-read AX elements for identity).
    func currentHoveredDockItemToken() -> UInt? {
        lastHoverToken
    }

    /// Live hovered app resolved from AX (DockDoor `getDockItemAppStatusUnderMouse`).
    func currentAppHoverInfo() -> DockHoverTarget.AppHoverInfo? {
        guard let item = getHoveredDockItemElement() else { return nil }
        return resolveAppHoverInfo(for: item)
    }

    /// Live selected dock item (DockDoor `getHoveredDockItemElement` → `getSelectedDockItem` only).
    func getHoveredDockItemElement() -> AXUIElement? {
        guard let listElement = dockAXList else { return nil }
        return selectedDockItem(in: listElement)
    }

    /// Whether the mouse is still over the dock item that opened the preview (DockDoor AX element equality).
    static func isHoveredDockItemMatching(_ shownItem: AXUIElement?) -> Bool {
        guard let shownItem else { return false }
        guard let current = activeObserver?.getHoveredDockItemElement() else { return false }
        return CFEqual(shownItem, current)
    }

    /// Whether the mouse is still over the dock item that opened the preview (token fallback).
    static func isHoveredTokenMatching(_ shownToken: UInt?) -> Bool {
        guard let shownToken, let current = lastHoveredTokenProvider?() else { return false }
        return shownToken == current
    }

    /// Live AX frame for the hovered dock item (updates during Dock magnification).
    func currentHoveredIconRect() -> CGRect? {
        guard let listElement = dockAXList,
              let item = selectedDockItem(in: listElement)
        else { return nil }
        return dockItemRect(item)
    }

    /// Rebuilds the Dock AX observer after sleep or a stale subscription (DockDoor `reset()`).
    func recoverFromSystemWake() {
        resetSubscription()
    }

    func resetSubscription() {
        coordinator.stop()
        dockPID = nil
        dockAXList = nil

        guard let dockApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.dock"
        }) else { return }

        let pid = dockApp.processIdentifier
        dockPID = pid
        let dockElement = AXUIElementCreateApplication(pid)
        guard let list = findDockIconList(in: dockElement) else { return }
        dockAXList = list

        coordinator.start(
            pid: pid,
            targetElement: list,
            notifications: [kAXSelectedChildrenChangedNotification as String]
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handleDockEvent()
            }
        }
    }

    private func startHealthCheck() {
        healthCheckTask?.cancel()
        healthCheckTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { return }
                self.performHealthCheck()
            }
        }
    }

    private func performHealthCheck() {
        let currentDockPID = NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == "com.apple.dock" }?
            .processIdentifier
        if currentDockPID != dockPID {
            resetSubscription()
            return
        }
        guard let list = dockAXList else {
            resetSubscription()
            return
        }
        var role: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(list, kAXRoleAttribute as CFString, &role)
        if err == .invalidUIElement || err == .cannotComplete || role == nil {
            resetSubscription()
            return
        }
        // AX notifications can stop while the list element still looks valid; poll selection as fallback.
        if DockPreviewDockPosition.isMouseInDockRegion(padding: 48) {
            onDockProximity?()
        }
        pollSelectedDockItemIfChanged(in: list)
        onPeriodicHealthCheck?()
    }

    private func installWakeObserverIfNeeded() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleWakeRecovery()
        }
    }

    private func scheduleWakeRecovery() {
        wakeRecoveryTask?.cancel()
        wakeRecoveryTask = Task { @MainActor [weak self] in
            var delayNanoseconds: UInt64 = 1_000_000_000
            var waitedNanoseconds: UInt64 = 0
            let maxWaitNanoseconds: UInt64 = 15_000_000_000
            while !Task.isCancelled, waitedNanoseconds < maxWaitNanoseconds {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
                guard !Task.isCancelled, let self else { return }
                waitedNanoseconds += delayNanoseconds
                if AXIsProcessTrusted() {
                    break
                }
                delayNanoseconds = min(delayNanoseconds * 2, maxWaitNanoseconds - waitedNanoseconds)
            }
            guard !Task.isCancelled, let self else { return }
            self.recoverFromSystemWake()
            self.onSystemWakeRecovery?()
        }
    }

    /// Polls dock selection when AX notifications may have gone silent (long uptime / Dock UI rebuild).
    private func pollSelectedDockItemIfChanged(in list: AXUIElement) {
        guard shouldSuppressSelectionPolling?() != true else { return }
        guard DockPreviewDockPosition.isMouseInDockRegion(padding: 48) else { return }
        pollSelectedDockItemIfChangedIgnoringSuppression(in: list)
    }

    /// Pointer-driven poll while the preview is open — runs even when the cursor is on the panel.
    func pollDockSelectionIfPointerInDockRegion() {
        guard DockPreviewDockPosition.isMouseInDockRegion(padding: 48),
              let list = dockAXList
        else { return }
        pollSelectedDockItemIfChangedIgnoringSuppression(in: list)
    }

    private func pollSelectedDockItemIfChangedIgnoringSuppression(in list: AXUIElement) {
        guard let item = selectedDockItem(in: list) else { return }
        let token = elementToken(item)
        guard token != lastHoverToken else { return }
        handleDockEvent()
    }

    private func findDockIconList(in element: AXUIElement) -> AXUIElement? {
        var result: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &result)
        guard let children = result as? [AXUIElement] else { return nil }
        for child in children {
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
            if (role as? String) == (kAXListRole as String) { return child }
        }
        return nil
    }

    private func handleDockEvent() {
        guard let listElement = dockAXList else { return }
        guard let item = selectedDockItem(in: listElement) else {
            lastHoverToken = nil
            lastAppHoverSignature = nil
            // DockDoor: no preview action when AX selection is empty — inactivity fade owns dismissal.
            return
        }

        let token = elementToken(item)

        if let folder = folderHoverInfo(for: item) {
            let hub = DockHubSettingsStore.load()
            guard hub.widgets.enableDockItemWidgets, settings().enableFolderWidget else {
                lastHoverToken = token
                lastAppHoverSignature = nil
                return
            }
            if token == lastHoverToken { return }
            lastHoverToken = token
            lastAppHoverSignature = nil
            onHoverBegan?(.folder(folder))
            return
        }

        guard let appInfo = resolveAppHoverInfo(for: item) else {
            lastHoverToken = nil
            lastAppHoverSignature = nil
            onHoverEnded?()
            return
        }

        if appInfo.bundleIdentifier == mainBundleID {
            lastHoverToken = nil
            lastAppHoverSignature = nil
            onHoverEnded?()
            return
        }

        let signature = "\(token)-\(appInfo.pid)-\(appInfo.bundleIdentifier ?? "")"
        if token == lastHoverToken, signature == lastAppHoverSignature { return }

        lastHoverToken = token
        lastAppHoverSignature = signature
        onHoverBegan?(.app(appInfo))
    }

    private func selectedDockItem(in list: AXUIElement) -> AXUIElement? {
        var selected: CFTypeRef?
        AXUIElementCopyAttributeValue(list, kAXSelectedChildrenAttribute as CFString, &selected)
        return (selected as? [AXUIElement])?.first
    }

    /// Resolve hovered app from dock AX item (DockDoor `getDockItemAppStatusUnderMouse`).
    private func resolveAppHoverInfo(for item: AXUIElement) -> DockHoverTarget.AppHoverInfo? {
        guard dockItemSubrole(item) == "AXApplicationDockItem" else { return nil }
        let iconRect = dockItemRect(item)
        let token = elementToken(item)

        guard let url = dockItemURL(item) else {
            guard let title = dockItemTitle(item),
                  let app = findRunningApplication(named: title)
            else { return nil }
            return DockHoverTarget.AppHoverInfo(
                pid: app.processIdentifier,
                appName: app.localizedName ?? title,
                bundleIdentifier: app.bundleIdentifier,
                iconRect: iconRect,
                dockItemToken: token
            )
        }

        let bundle = Bundle(url: url)
        guard let bundleID = bundle?.bundleIdentifier else {
            guard let title = dockItemTitle(item),
                  let app = findRunningApplication(named: title)
            else { return nil }
            return DockHoverTarget.AppHoverInfo(
                pid: app.processIdentifier,
                appName: app.localizedName ?? title,
                bundleIdentifier: app.bundleIdentifier,
                iconRect: iconRect,
                dockItemToken: token
            )
        }

        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if running.count > 1 {
            let index = dockInstanceIndex(for: item, bundleIdentifier: bundleID)
            if index < running.count {
                let app = running[index]
                return DockHoverTarget.AppHoverInfo(
                    pid: app.processIdentifier,
                    appName: app.localizedName ?? bundleID,
                    bundleIdentifier: bundleID,
                    iconRect: iconRect,
                    dockItemToken: token
                )
            }
        }
        if let app = running.first {
            return DockHoverTarget.AppHoverInfo(
                pid: app.processIdentifier,
                appName: app.localizedName ?? bundleID,
                bundleIdentifier: bundleID,
                iconRect: iconRect,
                dockItemToken: token
            )
        }

        let name = bundle?.infoDictionary?["CFBundleName"] as? String
            ?? url.deletingPathExtension().lastPathComponent
        return DockHoverTarget.AppHoverInfo(
            pid: 0,
            appName: name,
            bundleIdentifier: bundleID,
            iconRect: iconRect,
            dockItemToken: token
        )
    }

    private func findRunningApplication(named applicationName: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.localizedName == applicationName }
    }

    private func folderHoverInfo(for item: AXUIElement) -> DockHoverTarget.FolderHoverInfo? {
        let axURL = dockItemURL(item)
        let title = dockItemTitle(item)
        guard let folderURL = DockDockFolderItemResolver.resolveFolderURL(axURL: axURL, title: title) else {
            return nil
        }
        let displayTitle = title ?? FileManager.default.displayName(atPath: folderURL.path)
        if axURL?.pathExtension == "app", title != nil {
            DockPreviewWorklog.log("hover.folder.resolved", fields: [
                "title": displayTitle,
                "axURL": axURL?.path ?? "",
                "folder": folderURL.path,
            ])
        }
        return DockHoverTarget.FolderHoverInfo(
            url: folderURL,
            title: displayTitle,
            iconRect: dockItemRect(item),
            dockItemToken: elementToken(item)
        )
    }

    private func dockInstanceIndex(for hoveredItem: AXUIElement, bundleIdentifier: String) -> Int {
        guard let list = dockAXList,
              let allItems = dockListChildren(list)
        else { return 0 }
        let matching = allItems.filter { item in
            guard dockItemSubrole(item) == "AXApplicationDockItem",
                  let url = dockItemURL(item),
                  let bundle = Bundle(url: url)
            else { return false }
            return bundle.bundleIdentifier == bundleIdentifier
        }
        for (index, item) in matching.enumerated() where CFEqual(item, hoveredItem) {
            return index
        }
        return 0
    }

    private func dockListChildren(_ list: AXUIElement) -> [AXUIElement]? {
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(list, kAXChildrenAttribute as CFString, &children)
        return children as? [AXUIElement]
    }

    private func dockItemSubrole(_ item: AXUIElement) -> String? {
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(item, kAXSubroleAttribute as CFString, &subrole)
        return subrole as? String
    }

    private func dockItemURL(_ item: AXUIElement) -> URL? {
        var urlRef: CFTypeRef?
        AXUIElementCopyAttributeValue(item, kAXURLAttribute as CFString, &urlRef)
        return (urlRef as? NSURL)?.absoluteURL ?? urlRef as? URL
    }

    private func dockItemTitle(_ item: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleRef)
        return titleRef as? String
    }

    private func dockItemRect(_ item: AXUIElement) -> CGRect {
        var position: CFTypeRef?
        var size: CFTypeRef?
        AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &position)
        AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &size)
        var point = CGPoint.zero
        var cgSize = CGSize.zero
        if let posValue = position, CFGetTypeID(posValue) == AXValueGetTypeID() {
            AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
        }
        if let sizeValue = size, CFGetTypeID(sizeValue) == AXValueGetTypeID() {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &cgSize)
        }
        return CGRect(origin: point, size: cgSize)
    }

    private func elementToken(_ element: AXUIElement) -> UInt {
        UInt(bitPattern: ObjectIdentifier(element as AnyObject).hashValue)
    }
}
