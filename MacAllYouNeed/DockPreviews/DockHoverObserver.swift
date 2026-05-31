import AppKit
import ApplicationServices
import Foundation
import Platform

/// Observes the Dock for icon hover events using the shared AXObserverCoordinator (S1).
/// Detects which app icon the user is hovering via kAXSelectedChildrenChangedNotification.
@MainActor
final class DockHoverObserver {
    private let coordinator: AXObserverCoordinator
    private var dockPID: pid_t?
    private var dockAXList: AXUIElement?

    var onHoverBegan: ((pid_t, String) -> Void)?  // (app pid, app name)
    var onHoverEnded: (() -> Void)?

    init(coordinator: AXObserverCoordinator) {
        self.coordinator = coordinator
    }

    func start() {
        guard let dockApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.dock"
        }) else { return }
        let dockPID = dockApp.processIdentifier
        self.dockPID = dockPID

        // Find the Dock's AXList element (the icon list).
        let dockElement = AXUIElementCreateApplication(dockPID)
        dockAXList = findDockIconList(in: dockElement)

        // Subscribe to selection changes on the AXList child element.
        coordinator.start(
            pid: dockPID,
            targetElement: dockAXList,
            notifications: [kAXSelectedChildrenChangedNotification as String]
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handleDockEvent()
            }
        }
    }

    func stop() {
        coordinator.stop()
        dockPID = nil
        dockAXList = nil
    }

    private func findDockIconList(in element: AXUIElement) -> AXUIElement? {
        var result: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &result)
        guard let children = result as? [AXUIElement] else { return element }
        for child in children {
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
            if (role as? String) == (kAXListRole as String) { return child }
        }
        return element
    }

    private func handleDockEvent() {
        guard let listElement = dockAXList else { return }
        var selected: CFTypeRef?
        AXUIElementCopyAttributeValue(listElement, kAXSelectedChildrenAttribute as CFString, &selected)
        guard let selectedItems = selected as? [AXUIElement], let item = selectedItems.first else {
            onHoverEnded?()
            return
        }

        // Prefer matching by URL to a running app; fall back to the AX title.
        var urlRef: CFTypeRef?
        AXUIElementCopyAttributeValue(item, kAXURLAttribute as CFString, &urlRef)
        let url = urlRef as? URL

        if let url, let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL == url }) {
            onHoverBegan?(app.processIdentifier, app.localizedName ?? url.deletingPathExtension().lastPathComponent)
            return
        }

        // App not running — read the AX title for the name
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleRef)
        let title = titleRef as? String ?? url?.deletingPathExtension().lastPathComponent ?? "App"
        // No PID for non-running app; notify with pid=0 so caller can show a placeholder
        onHoverBegan?(0, title)
    }
}
