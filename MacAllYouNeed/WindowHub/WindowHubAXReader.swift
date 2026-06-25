import ApplicationServices
import CoreGraphics
import Foundation

enum WindowHubAXReader {
    struct WindowAttributes: Sendable {
        let title: String?
        let minimized: Bool
        let position: CGPoint?
        let size: CGSize?
    }

    private static let lock = NSLock()
    private static var preparedPIDs = Set<pid_t>()

    static func resetForRefresh() {
        lock.lock()
        preparedPIDs.removeAll()
        lock.unlock()
    }

    static func evict(pid: pid_t) {
        lock.lock()
        preparedPIDs.remove(pid)
        lock.unlock()
    }

    static func applicationElement(for pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        lock.lock()
        let alreadyPrepared = preparedPIDs.contains(pid)
        if !alreadyPrepared {
            preparedPIDs.insert(pid)
        }
        lock.unlock()
        if !alreadyPrepared {
            AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
        return element
    }

    static func readWindowAttributes(_ element: AXUIElement) -> WindowAttributes {
        var titleRef: CFTypeRef?
        var minimizedRef: CFTypeRef?
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &minimizedRef)
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
        return WindowAttributes(
            title: titleRef as? String,
            minimized: minimizedRef as? Bool ?? false,
            position: pointValue(positionRef),
            size: sizeValue(sizeRef)
        )
    }

    private static func pointValue(_ value: CFTypeRef?) -> CGPoint? {
        guard let value else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func sizeValue(_ value: CFTypeRef?) -> CGSize? {
        guard let value else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }
}
