import AppKit
import ApplicationServices
import Foundation

struct AXTargetMetadata: Equatable, Sendable {
    let bundleID: String?
    let pid: pid_t
    let role: String?
    let subrole: String?
    let isEditable: Bool

    var identityKey: String {
        "\(pid)|\(role ?? "?")|\(subrole ?? "?")"
    }
}

@MainActor
enum AXFocusedTextReader {
    static func snapshotFocused() -> AXTargetMetadata? {
        guard AXIsProcessTrusted() else { return nil }
        guard let element = focusedUIElement() else { return nil }

        let pid = pidOf(element) ?? 0
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        let role = stringAttribute(of: element, name: kAXRoleAttribute as CFString)
        let subrole = stringAttribute(of: element, name: kAXSubroleAttribute as CFString)

        var settable: DarwinBoolean = false
        let editableStatus = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        let isEditable = (editableStatus == .success) && settable.boolValue

        return AXTargetMetadata(
            bundleID: bundleID,
            pid: pid,
            role: role,
            subrole: subrole,
            isEditable: isEditable
        )
    }

    static func readValue(matching snapshot: AXTargetMetadata) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        guard let element = focusedUIElement() else { return nil }

        let currentPid = pidOf(element) ?? 0
        guard currentPid == snapshot.pid else { return nil }
        guard stringAttribute(of: element, name: kAXRoleAttribute as CFString) == snapshot.role else { return nil }
        guard stringAttribute(of: element, name: kAXSubroleAttribute as CFString) == snapshot.subrole else { return nil }

        return stringAttribute(of: element, name: kAXValueAttribute as CFString)
    }

    static func currentFocusedMatches(_ snapshot: AXTargetMetadata) -> Bool {
        guard let current = snapshotFocused() else { return false }
        return current.identityKey == snapshot.identityKey && current.bundleID == snapshot.bundleID
    }

    // MARK: - Private

    private static func focusedUIElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard status == .success, let ref = focusedRef else { return nil }
        let element = ref as! AXUIElement
        return element
    }

    private static func pidOf(_ element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        let status = AXUIElementGetPid(element, &pid)
        return status == .success ? pid : nil
    }

    private static func stringAttribute(of element: AXUIElement, name: CFString) -> String? {
        var ref: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, name, &ref)
        guard status == .success, let value = ref as? String else { return nil }
        return value
    }
}
