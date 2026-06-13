import ApplicationServices
import AppKit
import Foundation

/// Minimal AX attribute reads (DockDoor `AXUIElement` extension subset).
enum DockPreviewAXAttributes {
    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? Bool
    }

    static func point(_ element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    static func size(_ element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success,
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID()
        else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(axValue as! AXValue, .cgSize, &size) else { return nil }
        return size == .zero ? nil : size
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }
}

struct DockPreviewWindowCandidateAttributes {
    let title: String?
    let role: String?
    let subrole: String?
    let size: CGSize?
    let position: CGPoint?

    init(axWindow: AXUIElement) {
        title = DockPreviewAXAttributes.string(axWindow, kAXTitleAttribute as String)
        role = DockPreviewAXAttributes.string(axWindow, kAXRoleAttribute as String)
        subrole = DockPreviewAXAttributes.string(axWindow, kAXSubroleAttribute as String)
        size = DockPreviewAXAttributes.size(axWindow)
        position = DockPreviewAXAttributes.point(axWindow)
    }

    init(title: String?, role: String?, subrole: String?, size: CGSize?, position: CGPoint?) {
        self.title = title
        self.role = role
        self.subrole = subrole
        self.size = size
        self.position = position
    }
}
