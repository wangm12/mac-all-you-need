import AppKit
import ApplicationServices
import Foundation

/// Sendable summary of a focused AX element. Used for filter decisions, logging,
/// and identity comparison. Does NOT include the AX element reference, so it can
/// safely cross actor boundaries.
struct AXTargetMetadata: Equatable, Sendable {
    let bundleID: String?
    let pid: pid_t
    let role: String?
    let subrole: String?
    let isEditable: Bool

    /// Coarse identity key used for logging and same-app/same-role checks.
    /// **Not** sufficient by itself for privacy capture — two distinct text fields
    /// in the same app share this key. Use `AXTargetSnapshot` + `CFEqual` for real
    /// element identity.
    var identityKey: String {
        "\(pid)|\(role ?? "?")|\(subrole ?? "?")"
    }
}

/// Strong identity handle: holds the actual `AXUIElement` reference so subsequent
/// reads can verify they are operating on the same element via `CFEqual`. Lives
/// only on `@MainActor` because AXUIElement is a CFType that should be touched on
/// the main thread.
@MainActor
final class AXTargetSnapshot {
    let metadata: AXTargetMetadata
    let element: AXUIElement

    init(metadata: AXTargetMetadata, element: AXUIElement) {
        self.metadata = metadata
        self.element = element
    }
}

@MainActor
enum AXFocusedTextReader {
    static func snapshotFocused() -> AXTargetSnapshot? {
        guard AXIsProcessTrusted() else { return nil }
        guard let element = focusedUIElement() else { return nil }

        let pid = pidOf(element) ?? 0
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        let role = stringAttribute(of: element, name: kAXRoleAttribute as CFString)
        let subrole = stringAttribute(of: element, name: kAXSubroleAttribute as CFString)

        var settable: DarwinBoolean = false
        let editableStatus = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        let isEditable = (editableStatus == .success) && settable.boolValue

        let metadata = AXTargetMetadata(
            bundleID: bundleID,
            pid: pid,
            role: role,
            subrole: subrole,
            isEditable: isEditable
        )
        return AXTargetSnapshot(metadata: metadata, element: element)
    }

    /// Reads the focused element's value, but only if the currently focused element is
    /// the **same** AX element captured by `snapshot`. Element identity is verified
    /// via `CFEqual`, which AXUIElement implements based on the underlying logical
    /// element — distinct text fields in the same app correctly compare unequal.
    /// Re-checks the bundle and metadata as defense in depth (process restart, AX
    /// reuse). Returns nil on any mismatch or AX failure.
    static func readValue(matching snapshot: AXTargetSnapshot) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        guard let current = focusedUIElement() else { return nil }
        guard CFEqual(current, snapshot.element) else { return nil }
        guard pidOf(current) == snapshot.metadata.pid else { return nil }

        let bundleID = NSRunningApplication(processIdentifier: snapshot.metadata.pid)?.bundleIdentifier
        guard bundleID == snapshot.metadata.bundleID else { return nil }
        guard stringAttribute(of: current, name: kAXRoleAttribute as CFString) == snapshot.metadata.role else { return nil }
        guard stringAttribute(of: current, name: kAXSubroleAttribute as CFString) == snapshot.metadata.subrole else { return nil }

        return stringAttribute(of: current, name: kAXValueAttribute as CFString)
    }

    /// Cheap "is the snapshot still focused" check used by the polling loop. Verifies
    /// element identity via `CFEqual` plus pid sanity check. Bundle/role/subrole are
    /// not re-read here (the value-read path checks them again).
    static func currentFocusedMatches(_ snapshot: AXTargetSnapshot) -> Bool {
        guard let current = focusedUIElement() else { return false }
        guard CFEqual(current, snapshot.element) else { return false }
        guard pidOf(current) == snapshot.metadata.pid else { return false }
        return true
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
