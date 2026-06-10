import ApplicationServices
import Foundation
import Platform

@MainActor
enum CursorPaster {
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

        // Prefer replacing the current selection directly. This keeps behavior
        // aligned with "insert into active field" and avoids clipboard reliance.
        if isSettable(element, attribute: kAXSelectedTextAttribute as CFString),
           AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success {
            return true
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
        guard status == .success, let ref = focusedRef else { return nil }
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
