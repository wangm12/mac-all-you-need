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
    private var lastHoverToken: UInt?
    private var lastAppHoverSignature: String?
    private let mainBundleID = Bundle.main.bundleIdentifier

    var onHoverBegan: ((DockHoverTarget) -> Void)?
    var onHoverEnded: (() -> Void)?
    var settings: () -> DockPreviewSettings = { DockPreviewSettingsStore.load() }

    init(coordinator: AXObserverCoordinator) {
        self.coordinator = coordinator
    }

    func start() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)
        resetSubscription()
        startHealthCheck()
    }

    func stop() {
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

    /// Whether the mouse is still over the dock item that opened the preview (DockDoor AX element equality via token).
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
        }
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
            onHoverEnded?()
            return
        }

        let token = elementToken(item)

        if let folder = folderHoverInfo(for: item), settings().enableFolderWidget {
            if token == lastHoverToken { return }
            lastHoverToken = token
            lastAppHoverSignature = nil
            onHoverBegan?(.folder(folder))
            return
        }

        guard let appInfo = appHoverInfo(for: item) else {
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

    private func appHoverInfo(for item: AXUIElement) -> DockHoverTarget.AppHoverInfo? {
        guard dockItemSubrole(item) == "AXApplicationDockItem" else { return nil }
        guard let url = dockItemURL(item) else { return nil }

        let bundle = Bundle(url: url)
        let bundleID = bundle?.bundleIdentifier
        let iconRect = dockItemRect(item)

        if let bundleID, !bundleID.isEmpty {
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
                        dockItemToken: elementToken(item)
                    )
                }
            }
            if let app = running.first {
                return DockHoverTarget.AppHoverInfo(
                    pid: app.processIdentifier,
                    appName: app.localizedName ?? bundleID,
                    bundleIdentifier: bundleID,
                    iconRect: iconRect,
                    dockItemToken: elementToken(item)
                )
            }
            let name = bundle?.infoDictionary?["CFBundleName"] as? String
                ?? url.deletingPathExtension().lastPathComponent
            return DockHoverTarget.AppHoverInfo(
                pid: 0,
                appName: name,
                bundleIdentifier: bundleID,
                iconRect: iconRect,
                dockItemToken: elementToken(item)
            )
        }

        let title = dockItemTitle(item) ?? url.deletingPathExtension().lastPathComponent
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.caseInsensitiveCompare(title) == .orderedSame
        }) {
            return DockHoverTarget.AppHoverInfo(
                pid: app.processIdentifier,
                appName: app.localizedName ?? title,
                bundleIdentifier: app.bundleIdentifier,
                iconRect: iconRect,
                dockItemToken: elementToken(item)
            )
        }
        return nil
    }

    private func folderHoverInfo(for item: AXUIElement) -> DockHoverTarget.FolderHoverInfo? {
        guard dockItemSubrole(item) != "AXApplicationDockItem" else { return nil }
        guard let url = dockItemURL(item), url.pathExtension != "app" else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        let title = dockItemTitle(item) ?? FileManager.default.displayName(atPath: url.path)
        return DockHoverTarget.FolderHoverInfo(
            url: url,
            title: title,
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
        if let posValue = position { AXValueGetValue(posValue as! AXValue, .cgPoint, &point) }
        if let sizeValue = size { AXValueGetValue(sizeValue as! AXValue, .cgSize, &cgSize) }
        return CGRect(origin: point, size: cgSize)
    }

    private func elementToken(_ element: AXUIElement) -> UInt {
        UInt(bitPattern: ObjectIdentifier(element as AnyObject).hashValue)
    }
}
