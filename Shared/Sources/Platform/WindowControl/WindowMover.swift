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

        let didMove: Bool
        if element.isResizable {
            didMove = element.setSize(proposedFrame.size)
                && element.setPosition(proposedFrame.origin)
                && element.setSize(proposedFrame.size)
        } else {
            didMove = element.setPosition(proposedFrame.origin)
        }

        if let previousEnhancedUserInterface {
            enhancedUserInterfaceWriteSucceeded = element.setEnhancedUserInterfaceEnabled(previousEnhancedUserInterface)
                && enhancedUserInterfaceWriteSucceeded
        }

        return result(
            action: action,
            status: didMove && enhancedUserInterfaceWriteSucceeded ? .moved : .writeFailed,
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

    private func approximatelyEqual(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
    }

    private func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < 0.5
            && abs(lhs.origin.y - rhs.origin.y) < 0.5
            && approximatelyEqual(lhs.size, rhs.size)
    }
}

private extension CGRect {
    func preservingSize(_ size: CGSize, clampedTo bounds: CGRect, when shouldPreserveSize: Bool) -> CGRect {
        guard shouldPreserveSize else {
            return self
        }
        let maxX = max(bounds.minX, bounds.maxX - size.width)
        let maxY = max(bounds.minY, bounds.maxY - size.height)
        return CGRect(
            x: min(max(origin.x, bounds.minX), maxX),
            y: min(max(origin.y, bounds.minY), maxY),
            width: size.width,
            height: size.height
        )
    }
}

private extension WindowAction {
    var repeatedDisplayTargetAction: WindowAction? {
        switch self {
        case .leftHalf:
            .rightHalf
        case .rightHalf:
            .leftHalf
        case .topHalf:
            .bottomHalf
        case .bottomHalf:
            .topHalf
        case .topLeft, .topRight, .bottomLeft, .bottomRight,
             .maximize, .almostMaximize, .center, .restore, .nextDisplay, .previousDisplay:
            nil
        }
    }
}
