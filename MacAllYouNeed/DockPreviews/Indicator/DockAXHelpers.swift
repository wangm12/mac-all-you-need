import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum DockAXHelpers {
    static func dockIconFrame(for app: NSRunningApplication) -> CGRect? {
        guard let dockList = dockListElement(),
              let items = copyAXChildren(dockList)
        else { return nil }

        for item in items {
            guard copyStringAttribute(item, kAXSubroleAttribute) == (kAXApplicationDockItemSubrole as String) else {
                continue
            }
            guard let url = copyURLAttribute(item) else { continue }
            let bundleID = Bundle(url: url)?.bundleIdentifier
            if let bundleID, bundleID == app.bundleIdentifier {
                return elementRect(item)
            }
            if let title = copyStringAttribute(item, kAXTitleAttribute),
               app.localizedName?.caseInsensitiveCompare(title) == .orderedSame {
                return elementRect(item)
            }
        }
        return nil
    }

    static func dockListElement() -> AXUIElement? {
        guard let dockApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dock" }) else {
            return nil
        }
        let dockElement = AXUIElementCreateApplication(dockApp.processIdentifier)
        guard let children = copyAXChildren(dockElement) else { return nil }
        return children.first { copyStringAttribute($0, kAXRoleAttribute) == (kAXListRole as String) }
    }

    private static func copyAXChildren(_ element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? [AXUIElement]
    }

    private static func copyStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func copyURLAttribute(_ element: AXUIElement) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? URL
    }

    private static func elementRect(_ element: AXUIElement) -> CGRect {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
        var point = CGPoint.zero
        var size = CGSize.zero
        if let posValue = positionRef { AXValueGetValue(posValue as! AXValue, .cgPoint, &point) }
        if let sizeValue = sizeRef { AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) }
        return CGRect(origin: point, size: size)
    }

    /// Best-effort focused window for a running app, limited to known preview window IDs.
    static func focusedWindowID(for pid: pid_t, among candidates: [CGWindowID]) -> CGWindowID? {
        guard !candidates.isEmpty else { return nil }
        let candidateSet = Set(candidates)
        let appElement = AXUIElementCreateApplication(pid)
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
           let focusedRef {
            let windowElement = focusedRef as! AXUIElement
            if let matched = matchAXWindow(windowElement, pid: pid, among: candidateSet) {
                return matched
            }
        }
        return frontmostOnScreenWindowID(pid: pid, among: candidateSet)
    }

    private static func matchAXWindow(
        _ windowElement: AXUIElement,
        pid: pid_t,
        among candidates: Set<CGWindowID>
    ) -> CGWindowID? {
        let axTitle = copyStringAttribute(windowElement, kAXTitleAttribute as String)
        let axFrame = elementRect(windowElement)
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        for info in list {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let number = info[kCGWindowNumber as String] as? CGWindowID,
                  candidates.contains(number)
            else { continue }

            if let axTitle, !axTitle.isEmpty {
                let windowTitle = info[kCGWindowName as String] as? String ?? ""
                if windowTitle == axTitle { return number }
            }

            if let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
               let x = bounds["X"], let y = bounds["Y"],
               let w = bounds["Width"], let h = bounds["Height"] {
                let cgBounds = CGRect(x: x, y: y, width: w, height: h)
                if cgBounds.equalTo(axFrame) || cgBounds.intersects(axFrame) {
                    return number
                }
            }
        }
        return nil
    }

    private static func frontmostOnScreenWindowID(pid: pid_t, among candidates: Set<CGWindowID>) -> CGWindowID? {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }
        for info in list {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let number = info[kCGWindowNumber as String] as? CGWindowID,
                  candidates.contains(number)
            else { continue }
            return number
        }
        return nil
    }
}
