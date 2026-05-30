import Core
import CoreGraphics

public protocol WindowMovableElement: AnyObject {
    var frame: CGRect { get }
    var isResizable: Bool { get }
    var isMovable: Bool { get }
    var isSupportedForWindowControl: Bool { get }
    var enhancedUserInterfaceEnabled: Bool? { get }

    func setEnhancedUserInterfaceEnabled(_ enabled: Bool) -> Bool
    func setPosition(_ position: CGPoint) -> Bool
    func setSize(_ size: CGSize) -> Bool
}

public enum WindowMovementStatus: Equatable, Sendable {
    case moved
    case unsupportedWindow
    case noDisplay
    case noTargetFrame
    case fixedSizeWindow
    case writeFailed
}

public struct WindowMovementResult: Equatable, Sendable {
    public let action: WindowAction
    public let status: WindowMovementStatus
    public let originalFrame: CGRect
    public let proposedFrame: CGRect?
    public let resultingFrame: CGRect

    public init(
        action: WindowAction,
        status: WindowMovementStatus,
        originalFrame: CGRect,
        proposedFrame: CGRect?,
        resultingFrame: CGRect
    ) {
        self.action = action
        self.status = status
        self.originalFrame = originalFrame
        self.proposedFrame = proposedFrame
        self.resultingFrame = resultingFrame
    }
}

public final class WindowMover {
    private let screenDetector: any WindowScreenDetecting
    private let geometry: WindowGeometryCalculator

    public init(
        screenDetector: any WindowScreenDetecting = WindowScreenDetector.current(),
        geometry: WindowGeometryCalculator = WindowGeometryCalculator()
    ) {
        self.screenDetector = screenDetector
        self.geometry = geometry
    }

    public func move(
        _ element: any WindowMovableElement,
        action: WindowAction,
        previousResult: WindowMovementResult? = nil
    ) -> WindowMovementResult {
        let originalFrame = element.frame
        guard element.isSupportedForWindowControl, element.isMovable, isValid(frame: originalFrame) else {
            return result(
                action: action,
                status: .unsupportedWindow,
                originalFrame: originalFrame,
                proposedFrame: nil,
                element: element
            )
        }

        guard let proposedFrame = targetFrame(
            for: action,
            currentFrame: originalFrame,
            preserveSize: !element.isResizable,
            previousResult: previousResult
        ) else {
            return result(
                action: action,
                status: .noTargetFrame,
                originalFrame: originalFrame,
                proposedFrame: nil,
                element: element
            )
        }

        return moveValidated(
            element,
            action: resultingAction(for: action, currentFrame: originalFrame, previousResult: previousResult) ?? action,
            originalFrame: originalFrame,
            proposedFrame: proposedFrame
        )
    }

    public func move(
        _ element: any WindowMovableElement,
        to proposedFrame: CGRect,
        action: WindowAction
    ) -> WindowMovementResult {
        let originalFrame = element.frame
        guard element.isSupportedForWindowControl, element.isMovable, isValid(frame: originalFrame) else {
            return result(
                action: action,
                status: .unsupportedWindow,
                originalFrame: originalFrame,
                proposedFrame: nil,
                element: element
            )
        }

        guard isValid(frame: proposedFrame) else {
            return result(
                action: action,
                status: .noTargetFrame,
                originalFrame: originalFrame,
                proposedFrame: nil,
                element: element
            )
        }

        return moveValidated(
            element,
            action: action,
            originalFrame: originalFrame,
            proposedFrame: proposedFrame
        )
    }

    private func moveValidated(
        _ element: any WindowMovableElement,
        action: WindowAction,
        originalFrame: CGRect,
        proposedFrame: CGRect
    ) -> WindowMovementResult {
        let sizeChanges = !approximatelyEqual(originalFrame.size, proposedFrame.size)
        guard !sizeChanges || element.isResizable else {
            return result(
                action: action,
                status: .fixedSizeWindow,
                originalFrame: originalFrame,
                proposedFrame: proposedFrame,
                element: element
            )
        }

        var enhancedUserInterfaceWriteSucceeded = true
        let previousEnhancedUserInterface = element.enhancedUserInterfaceEnabled
        if previousEnhancedUserInterface != nil {
            enhancedUserInterfaceWriteSucceeded = element.setEnhancedUserInterfaceEnabled(false)
        }

        // Always run every write regardless of individual return values. AX
        // attribute-set return codes are unreliable for size/position — apps can
        // accept a write but clamp the value silently, or reject a write whose
        // effect actually takes hold. Short-circuiting via && caused us to skip
        // the position write whenever the first size write returned false, which
        // is the root cause of "Chrome / Slack / Office land at the wrong size."
        if element.isResizable {
            _ = element.setSize(proposedFrame.size)
            _ = element.setPosition(proposedFrame.origin)
            _ = element.setSize(proposedFrame.size)
        } else {
            _ = element.setPosition(proposedFrame.origin)
        }

        clampOffscreenWindow(element)

        if let previousEnhancedUserInterface {
            enhancedUserInterfaceWriteSucceeded = element.setEnhancedUserInterfaceEnabled(previousEnhancedUserInterface)
                && enhancedUserInterfaceWriteSucceeded
        }

        let actualFrame = element.frame
        let writeLandedSomewhereValid = isValid(frame: actualFrame)

        return result(
            action: action,
            status: writeLandedSomewhereValid && enhancedUserInterfaceWriteSucceeded ? .moved : .writeFailed,
            originalFrame: originalFrame,
            proposedFrame: proposedFrame,
            element: element
        )
    }

    private func targetFrame(
        for action: WindowAction,
        currentFrame: CGRect,
        preserveSize: Bool,
        previousResult: WindowMovementResult?
    ) -> CGRect? {
        guard let currentScreen = screenDetector.screen(containing: currentFrame) else {
            return nil
        }

        if let repeatedDisplayFrame = repeatedDisplayFrame(
            for: action,
            currentFrame: currentFrame,
            currentScreen: currentScreen,
            preserveSize: preserveSize,
            previousResult: previousResult
        ) {
            return repeatedDisplayFrame
        }

        switch action {
        case .nextDisplay:
            guard let targetScreen = screenDetector.nextScreen(after: currentScreen) else {
                return nil
            }
            return geometry.rectForMovingDisplay(
                currentFrame: currentFrame,
                sourceVisibleFrame: currentScreen.visibleFrame,
                targetVisibleFrame: targetScreen.visibleFrame
            ).preservingSize(currentFrame.size, clampedTo: targetScreen.visibleFrame, when: preserveSize)
        case .previousDisplay:
            guard let targetScreen = screenDetector.previousScreen(before: currentScreen) else {
                return nil
            }
            return geometry.rectForMovingDisplay(
                currentFrame: currentFrame,
                sourceVisibleFrame: currentScreen.visibleFrame,
                targetVisibleFrame: targetScreen.visibleFrame
            ).preservingSize(currentFrame.size, clampedTo: targetScreen.visibleFrame, when: preserveSize)
        default:
            return geometry.rect(
                for: action,
                visibleFrame: currentScreen.visibleFrame,
                currentSize: currentFrame.size
            )
        }
    }

    private func repeatedDisplayFrame(
        for action: WindowAction,
        currentFrame: CGRect,
        currentScreen: WindowControlScreen,
        preserveSize: Bool,
        previousResult: WindowMovementResult?
    ) -> CGRect? {
        guard let previousResult,
              previousResult.status == .moved,
              previousResult.action == action,
              approximatelyEqual(previousResult.resultingFrame, currentFrame),
              let targetAction = action.repeatedDisplayTargetAction,
              let targetScreen = repeatedDisplayTargetScreen(for: action, from: currentScreen)
        else {
            return nil
        }

        return geometry.rect(
            for: targetAction,
            visibleFrame: targetScreen.visibleFrame,
            currentSize: currentFrame.size
        )?.preservingSize(currentFrame.size, clampedTo: targetScreen.visibleFrame, when: preserveSize)
    }

    private func resultingAction(
        for action: WindowAction,
        currentFrame: CGRect,
        previousResult: WindowMovementResult?
    ) -> WindowAction? {
        guard let previousResult,
              previousResult.status == .moved,
              previousResult.action == action,
              approximatelyEqual(previousResult.resultingFrame, currentFrame),
              let currentScreen = screenDetector.screen(containing: currentFrame),
              repeatedDisplayTargetScreen(for: action, from: currentScreen) != nil
        else {
            return nil
        }
        return action.repeatedDisplayTargetAction
    }

    private func repeatedDisplayTargetScreen(
        for action: WindowAction,
        from currentScreen: WindowControlScreen
    ) -> WindowControlScreen? {
        switch action {
        case .leftHalf:
            return screenDetector.previousScreen(before: currentScreen)
        case .rightHalf:
            return screenDetector.nextScreen(after: currentScreen)
        case .topHalf:
            return nearestScreenAbove(currentScreen)
        case .bottomHalf:
            return nearestScreenBelow(currentScreen)
        case .topLeft, .topRight, .bottomLeft, .bottomRight,
             .maximize, .almostMaximize, .center, .restore, .nextDisplay, .previousDisplay:
            return nil
        }
    }

    private func nearestScreenAbove(_ currentScreen: WindowControlScreen) -> WindowControlScreen? {
        screenDetector.screens
            .filter { $0 != currentScreen && $0.frame.maxY <= currentScreen.frame.minY }
            .max { lhs, rhs in lhs.frame.maxY < rhs.frame.maxY }
    }

    private func nearestScreenBelow(_ currentScreen: WindowControlScreen) -> WindowControlScreen? {
        screenDetector.screens
            .filter { $0 != currentScreen && $0.frame.minY >= currentScreen.frame.maxY }
            .min { lhs, rhs in lhs.frame.minY < rhs.frame.minY }
    }

    private func result(
        action: WindowAction,
        status: WindowMovementStatus,
        originalFrame: CGRect,
        proposedFrame: CGRect?,
        element: any WindowMovableElement
    ) -> WindowMovementResult {
        WindowMovementResult(
            action: action,
            status: status,
            originalFrame: originalFrame,
            proposedFrame: proposedFrame,
            resultingFrame: element.frame
        )
    }

    private func isValid(frame: CGRect) -> Bool {
        !frame.isNull && !frame.isEmpty && frame.width.isFinite && frame.height.isFinite
    }
}

public extension WindowMover {
    /// Computes the target frame for an action without applying it. Returns the
    /// same rect `move(_:action:)` would write, or `nil` when no window/display
    /// is available. Used by the radial menu live preview.
    func proposedFrame(
        for action: WindowAction,
        element: any WindowMovableElement
    ) -> CGRect? {
        let originalFrame = element.frame
        guard element.isSupportedForWindowControl, element.isMovable, isValid(frame: originalFrame) else {
            return nil
        }
        return targetFrame(
            for: action,
            currentFrame: originalFrame,
            preserveSize: !element.isResizable,
            previousResult: nil
        )
    }
}

private extension WindowMover {
    func approximatelyEqual(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
    }

    func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < 0.5
            && abs(lhs.origin.y - rhs.origin.y) < 0.5
            && approximatelyEqual(lhs.size, rhs.size)
    }
    func clampOffscreenWindow(_ element: any WindowMovableElement) {
        let actual = element.frame
        guard isValid(frame: actual),
              let screen = screenDetector.screen(containing: actual)
        else {
            return
        }

        let visibleFrame = screen.visibleFrame
        var clamped = actual
        if clamped.maxX > visibleFrame.maxX {
            clamped.origin.x = max(visibleFrame.minX, visibleFrame.maxX - clamped.width)
        } else if clamped.minX < visibleFrame.minX {
            clamped.origin.x = visibleFrame.minX
        }
        if clamped.maxY > visibleFrame.maxY {
            clamped.origin.y = max(visibleFrame.minY, visibleFrame.maxY - clamped.height)
        } else if clamped.minY < visibleFrame.minY {
            clamped.origin.y = visibleFrame.minY
        }

        if clamped.origin != actual.origin {
            _ = element.setPosition(clamped.origin)
        }
    }
}
