import AppKit
import ApplicationServices
import Core
import Platform

/// Modifier + scroll wheel resizes the frontmost window (Tangrid-style).
enum WindowScrollResizeController {
    static func handleScroll(deltaY: Int, shiftHeld: Bool, settings: WindowControlSettings) -> Bool {
        guard settings.scrollResizeEnabled else { return false }
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let axWindow = value
        else { return false }
        let element = WindowAccessibilityElement(axWindow as! AXUIElement)
        guard element.isSupportedForWindowControl else { return false }
        var frame = element.frame
        guard !frame.isNull, !frame.isEmpty else { return false }

        let step = max(12, Int(frame.height * 0.02))
        let delta = CGFloat(deltaY > 0 ? -step : step)
        if shiftHeld {
            frame.size.width = max(200, frame.width + delta)
        } else {
            frame.size.height = max(120, frame.height + delta)
        }
        return element.setSize(frame.size)
    }
}
