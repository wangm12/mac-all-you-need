import AppKit
import ApplicationServices
import Core
import Platform

@MainActor
final class WindowKeyboardActionPerformer: WindowControlActionPerforming {
    private struct ResolvedWindow {
        let element: WindowAccessibilityElement
        let identity: WindowIdentity
    }

    private let mover: WindowMover
    private var pendingWindow: ResolvedWindow?
    private var previousResult: WindowMovementResult?
    private var previousIdentity: WindowIdentity?
    var repeatHalfAcrossDisplays: Bool {
        get { mover.repeatHalfAcrossDisplays }
        set { mover.repeatHalfAcrossDisplays = newValue }
    }

    init(mover: WindowMover = WindowMover()) {
        self.mover = mover
    }

    var currentIdentity: WindowIdentity? {
        let resolved = resolveFocusedWindow()
        pendingWindow = resolved
        return resolved?.identity
    }

    func perform(_ action: WindowAction, restoreFrame: CGRect?) -> WindowMovementResult? {
        let resolved = pendingWindow ?? resolveFocusedWindow()
        pendingWindow = nil
        guard let resolved else { return nil }
        if action == .restore, let restoreFrame {
            let result = mover.move(resolved.element, to: restoreFrame, action: action)
            previousResult = result
            previousIdentity = resolved.identity
            return result
        }
        let result = mover.move(
            resolved.element,
            action: action,
            previousResult: resolved.identity.matchesSameWindow(as: previousIdentity) ? previousResult : nil
        )
        previousResult = result
        previousIdentity = resolved.identity
        return result
    }

    private func resolveFocusedWindow() -> ResolvedWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let axWindow = value
        else {
            return nil
        }

        let element = WindowAccessibilityElement(axWindow as! AXUIElement)
        guard element.isSupportedForWindowControl else {
            return nil
        }
        return ResolvedWindow(
            element: element,
            identity: WindowIdentity(
                pid: element.processIdentifier,
                cgWindowID: nil,
                titleHash: element.windowTitleHash,
                frameFingerprint: element.frameFingerprint
            )
        )
    }
}

private extension WindowIdentity {
    func matchesSameWindow(as other: WindowIdentity?) -> Bool {
        guard let other, pid == other.pid else {
            return false
        }
        if let cgWindowID, let otherCGWindowID = other.cgWindowID {
            return cgWindowID == otherCGWindowID
        }
        if let titleHash, let otherTitleHash = other.titleHash {
            return titleHash == otherTitleHash
        }
        return frameFingerprint == other.frameFingerprint
    }
}
