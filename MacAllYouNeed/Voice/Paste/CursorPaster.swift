import AppKit
import ApplicationServices
import Foundation
import Platform

@MainActor
enum CursorPaster {
    // MARK: - Role classification for writability detection

    private static let nativeWritableRoles: Set<String> = [
        "AXTextArea", "AXTextField", "AXSearchField", "AXComboBox",
    ]
    private static let genericEditableRoles: Set<String> = [
        "AXWebArea", "AXGroup", "AXLayoutArea", "AXScrollArea", "AXDocument", "AXUnknown",
    ]
    private static let nonEditableRoles: Set<String> = [
        "AXWindow", "AXButton", "AXStaticText", "AXToolbar",
        "AXMenuBar", "AXMenu", "AXMenuItem", "AXList", "AXTable", "AXRow",
    ]

    private static func isWritableTextInputElement(_ element: AXUIElement) -> Bool {
        guard let role = stringAttribute(of: element, name: kAXRoleAttribute as CFString) else { return false }
        if nonEditableRoles.contains(role) { return false }
        if nativeWritableRoles.contains(role) { return true }
        if genericEditableRoles.contains(role) {
            var settable: DarwinBoolean = false
            let status = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
            if status == .success, settable.boolValue { return true }
            var rangeRef: CFTypeRef?
            return AXUIElementCopyAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, &rangeRef
            ) == .success
        }
        return false
    }

    private static func pidOfFocusedElement() -> pid_t? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef
        ) == .success, let ref = focusedRef else { return nil }
        let element = ref as! AXUIElement
        var pid: pid_t = 0
        return AXUIElementGetPid(element, &pid) == .success ? pid : nil
    }
    enum DeliveryPath: String, Equatable {
        case preferredAX
        case focusedAX
        case commandV
        case clipboardOnly
    }

    enum FailureReason: String, Equatable {
        case accessibilityPermissionMissing
        case targetNotWritable
        case focusUnavailable
        case commandVUnavailable
    }

    struct Result {
        let accessibilityTrusted: Bool
        let deliveryPath: DeliveryPath
        let failureReason: FailureReason?

        var insertedIntoActiveInput: Bool {
            deliveryPath == .preferredAX || deliveryPath == .focusedAX || deliveryPath == .commandV
        }
    }

    static func paste(_ text: String, preferredTarget: AXTargetSnapshot? = nil) async -> Result {
        let accessibilityTrusted = AXIsProcessTrusted()
        if accessibilityTrusted {
            if let preferredTarget,
               insertUsingAccessibility(text, element: preferredTarget.element)
            {
                return Result(
                    accessibilityTrusted: true,
                    deliveryPath: .preferredAX,
                    failureReason: nil
                )
            }
            if let element = focusedUIElement(),
               insertUsingAccessibility(text, element: element)
            {
                return Result(
                    accessibilityTrusted: true,
                    deliveryPath: .focusedAX,
                    failureReason: nil
                )
            }
        }

        // Re-activate target app if focus was stolen (HUD or Esc monitor may have taken it).
        let targetPID = preferredTarget?.metadata.pid ?? pidOfFocusedElement()
        if let pid = targetPID,
           let targetApp = NSRunningApplication(processIdentifier: pid),
           NSWorkspace.shared.frontmostApplication?.processIdentifier != pid
        {
            targetApp.activate(options: [.activateIgnoringOtherApps])
            try? await Task.sleep(for: .milliseconds(50))
        }

        let outcome = await PasteInjector.pasteWithRestore(text, restoreOnManualPasteRequired: false)
        if outcome.result == .injected {
            return Result(
                accessibilityTrusted: accessibilityTrusted,
                deliveryPath: .commandV,
                failureReason: accessibilityTrusted ? .targetNotWritable : .accessibilityPermissionMissing
            )
        }

        let failureReason: FailureReason
        if !accessibilityTrusted {
            failureReason = .accessibilityPermissionMissing
        } else if focusedUIElement() == nil {
            failureReason = .focusUnavailable
        } else {
            failureReason = .commandVUnavailable
        }
        return Result(
            accessibilityTrusted: accessibilityTrusted,
            deliveryPath: .clipboardOnly,
            failureReason: failureReason
        )
    }

    private static func insertUsingAccessibility(_ text: String, element: AXUIElement) -> Bool {
        // 100ms timeout prevents multi-second hangs on unresponsive apps while
        // still leaving room for apps under transient load.
        AXUIElementSetMessagingTimeout(element, 0.1)

        // Reject elements that are not writable text inputs.
        guard isWritableTextInputElement(element) else { return false }

        // Snapshot value before write so we can verify the write actually landed.
        let valueBefore = stringAttribute(of: element, name: kAXValueAttribute as CFString)

        // Prefer replacing the current selection directly. This keeps behavior
        // aligned with "insert into active field" and avoids clipboard reliance.
        if isSettable(element, attribute: kAXSelectedTextAttribute as CFString),
           AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success
        {
            // Verify the write wasn't silently ignored (e.g. Chrome accepts but resets).
            if let before = valueBefore {
                let valueAfter = stringAttribute(of: element, name: kAXValueAttribute as CFString)
                if valueAfter == before {
                    // Write was accepted but value didn't change — fall through.
                } else {
                    return true
                }
            } else {
                // No pre-snapshot available (web content, sandboxed apps). Cannot verify
                // the write landed — Chrome and Electron return .success but silently discard
                // AX writes to web inputs. Fall through to Cmd+V which handles browsers.
                return false
            }
        }

        // Fallback for controls that do not expose selected-text writes but do
        // expose value + selected range writes.
        guard isSettable(element, attribute: kAXValueAttribute as CFString),
              let current = stringAttribute(of: element, name: kAXValueAttribute as CFString),
              let selectedRange = selectedTextRange(of: element)
        else {
            return false
        }

        let nsCurrent = current as NSString
        let utf16Length = nsCurrent.length
        let safeLocation = min(max(selectedRange.location, 0), utf16Length)
        let safeLength = min(max(selectedRange.length, 0), utf16Length - safeLocation)
        let safeRange = NSRange(location: safeLocation, length: safeLength)

        let replaced = nsCurrent.replacingCharacters(in: safeRange, with: text)
        let writeStatus = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, replaced as CFTypeRef)
        guard writeStatus == .success else { return false }

        var caret = CFRange(location: safeLocation + (text as NSString).length, length: 0)
        if let caretValue = AXValueCreate(.cfRange, &caret) {
            _ = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, caretValue)
        }

        return true
    }

    private static func focusedUIElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard status == .success,
              let ref = focusedRef,
              CFGetTypeID(ref) == AXUIElementGetTypeID()
        else { return nil }
        return (ref as! AXUIElement)
    }

    private static func isSettable(_ element: AXUIElement, attribute: CFString) -> Bool {
        var settable: DarwinBoolean = false
        let status = AXUIElementIsAttributeSettable(element, attribute, &settable)
        return status == .success && settable.boolValue
    }

    private static func stringAttribute(of element: AXUIElement, name: CFString) -> String? {
        var ref: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, name, &ref)
        guard status == .success, let value = ref as? String else { return nil }
        return value
    }

    private static func selectedTextRange(of element: AXUIElement) -> CFRange? {
        var ref: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &ref)
        guard status == .success,
              let raw = ref,
              CFGetTypeID(raw) == AXValueGetTypeID()
        else {
            return nil
        }

        let value = raw as! AXValue
        guard AXValueGetType(value) == .cfRange else { return nil }

        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(value, .cfRange, &range) else { return nil }
        return range
    }
}
