import ApplicationServices
import CoreGraphics
import Foundation

public final class WindowAccessibilityElement: WindowTargetElement {
    private let element: AXUIElement

    public init(_ element: AXUIElement) {
        self.element = element
    }

    public static func windows(for processIdentifier: pid_t) -> [WindowAccessibilityElement] {
        let appElement = AXUIElementCreateApplication(processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement]
        else {
            return []
        }
        return elements.map(WindowAccessibilityElement.init)
    }

    public var frame: CGRect {
        guard let position = pointAttribute(kAXPositionAttribute as CFString),
              let size = sizeAttribute(kAXSizeAttribute as CFString)
        else {
            return .null
        }
        return CGRect(origin: position, size: size)
    }

    public var processIdentifier: pid_t {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else {
            return 0
        }
        return pid
    }

    public var windowTitleHash: Int? {
        stringAttribute(kAXTitleAttribute as CFString)?.hashValue
    }

    public var frameFingerprint: Int? {
        let frame = frame
        guard !frame.isNull, !frame.isEmpty else {
            return nil
        }
        var hasher = Hasher()
        hasher.combine(Int(frame.origin.x.rounded()))
        hasher.combine(Int(frame.origin.y.rounded()))
        hasher.combine(Int(frame.size.width.rounded()))
        hasher.combine(Int(frame.size.height.rounded()))
        return hasher.finalize()
    }

    public var isResizable: Bool {
        isAttributeSettable(kAXSizeAttribute as CFString)
    }

    public var isMovable: Bool {
        isAttributeSettable(kAXPositionAttribute as CFString)
    }

    public var isSupportedForWindowControl: Bool {
        guard role == "AXWindow" else {
            return false
        }
        if isFullScreen || role == "AXSheet" {
            return false
        }
        if let subrole, unsupportedSubroles.contains(subrole) {
            return false
        }
        return true
    }

    public var enhancedUserInterfaceEnabled: Bool? {
        boolAttribute("AXEnhancedUserInterface" as CFString)
    }

    public func setEnhancedUserInterfaceEnabled(_ enabled: Bool) -> Bool {
        setBoolAttribute(enabled, name: "AXEnhancedUserInterface" as CFString)
    }

    public func setPosition(_ position: CGPoint) -> Bool {
        var mutablePosition = position
        guard let value = AXValueCreate(.cgPoint, &mutablePosition) else {
            return false
        }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
    }

    public func setSize(_ size: CGSize) -> Bool {
        var mutableSize = size
        guard let value = AXValueCreate(.cgSize, &mutableSize) else {
            return false
        }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value) == .success
    }

    private var role: String? {
        stringAttribute(kAXRoleAttribute as CFString)
    }

    private var subrole: String? {
        stringAttribute(kAXSubroleAttribute as CFString)
    }

    private var isFullScreen: Bool {
        boolAttribute("AXFullScreen" as CFString) == true
    }

    private var unsupportedSubroles: Set<String> {
        ["AXSystemDialog", "AXDialog", "AXFloatingWindow", "AXUnknown"]
    }

    private func isAttributeSettable(_ name: CFString) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, name, &settable) == .success && settable.boolValue
    }

    private func pointAttribute(_ name: CFString) -> CGPoint? {
        guard let rawValue = copyAttribute(name),
              CFGetTypeID(rawValue) == AXValueGetTypeID()
        else {
            return nil
        }
        let value = rawValue as! AXValue
        guard AXValueGetType(value) == .cgPoint else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func sizeAttribute(_ name: CFString) -> CGSize? {
        guard let rawValue = copyAttribute(name),
              CFGetTypeID(rawValue) == AXValueGetTypeID()
        else {
            return nil
        }
        let value = rawValue as! AXValue
        guard AXValueGetType(value) == .cgSize else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else {
            return nil
        }
        return size
    }

    private func stringAttribute(_ name: CFString) -> String? {
        copyAttribute(name) as? String
    }

    private func boolAttribute(_ name: CFString) -> Bool? {
        guard let rawValue = copyAttribute(name),
              CFGetTypeID(rawValue) == CFBooleanGetTypeID()
        else {
            return nil
        }
        return CFBooleanGetValue((rawValue as! CFBoolean))
    }

    private func setBoolAttribute(_ enabled: Bool, name: CFString) -> Bool {
        let value: CFBoolean = enabled ? kCFBooleanTrue! : kCFBooleanFalse!
        return AXUIElementSetAttributeValue(element, name, value) == .success
    }

    private func copyAttribute(_ name: CFString) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else {
            return nil
        }
        return value as AnyObject?
    }
}
