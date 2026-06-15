import Core
import CoreGraphics
import Foundation

public protocol WindowMovableElement: AnyObject {
    var frame: CGRect { get }
    var isResizable: Bool { get }
    var isMovable: Bool { get }
    var isSupportedForWindowControl: Bool { get }
    var enhancedUserInterfaceEnabled: Bool? { get }

    func snapshot() -> WindowSnapshot
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
    private var pendingCrossDisplayRetry: DispatchWorkItem?
    private var moveAnimationTimer: Timer?
    private var moveAnimationGeneration = 0
    /// Captured before setting AXEnhancedUserInterface=false; restored by cancelInFlightMoveAnimation.
    private var savedEnhancedUserInterface: (element: any WindowMovableElement, value: Bool)?
    /// Schedules the bounded cross-display retry. Overridable in tests.
    var crossDisplayRetryScheduler: (@escaping () -> Void) -> Void = { work in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025, execute: work)
    }

    public var animationConfiguration = WindowMoveAnimationConfiguration.instant
    /// When false (default), pressing the same half shortcut again keeps the window on the
    /// current display instead of jumping to the adjacent monitor (Rectangle-style).
    public var repeatHalfAcrossDisplays: Bool = false
    /// When true, window moves interpolate over a short stepped AX animation.
    public var animateMoves: Bool = false

    public init(
        screenDetector: any WindowScreenDetecting = LiveWindowScreenDetector(),
        geometry: WindowGeometryCalculator = WindowGeometryCalculator()
    ) {
        self.screenDetector = screenDetector
        self.geometry = geometry
    }

    /// Cancels a pending async cross-display retry (used when a newer action supersedes).
    public func cancelPendingCrossDisplayRetry() {
        pendingCrossDisplayRetry?.cancel()
        pendingCrossDisplayRetry = nil
    }

    /// Cancels an in-flight stepped move animation and restores AXEnhancedUserInterface
    /// if it was disabled for the animation that is being cancelled.
    public func cancelInFlightMoveAnimation() {
        moveAnimationGeneration += 1
        moveAnimationTimer?.invalidate()
        moveAnimationTimer = nil
        if let saved = savedEnhancedUserInterface {
            _ = saved.element.setEnhancedUserInterfaceEnabled(saved.value)
            savedEnhancedUserInterface = nil
        }
    }

    public func move(
        _ element: any WindowMovableElement,
        action: WindowAction,
        previousResult: WindowMovementResult? = nil
    ) -> WindowMovementResult {
        move(element, snapshot: element.snapshot(), action: action, previousResult: previousResult)
    }

    /// Avoids a second snapshot() call when the caller already has one (e.g. after resolve).
    public func move(
        _ element: any WindowMovableElement,
        snapshot snap: WindowSnapshot,
        action: WindowAction,
        previousResult: WindowMovementResult? = nil
    ) -> WindowMovementResult {
        let originalFrame = snap.frame
        guard snap.isSupportedForWindowControl, snap.isMovable, isValid(frame: originalFrame) else {
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
            preserveSize: !snap.isResizable,
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

        let resolvedAction = resultingAction(
            for: action,
            currentFrame: originalFrame,
            previousResult: previousResult
        ) ?? action

        return moveValidated(
            element,
            snap: snap,
            action: resolvedAction,
            originalFrame: originalFrame,
            proposedFrame: proposedFrame
        )
    }

    public func move(
        _ element: any WindowMovableElement,
        to proposedFrame: CGRect,
        action: WindowAction
    ) -> WindowMovementResult {
        let snap = element.snapshot()
        let originalFrame = snap.frame
        guard snap.isSupportedForWindowControl, snap.isMovable, isValid(frame: originalFrame) else {
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
            snap: snap,
            action: action,
            originalFrame: originalFrame,
            proposedFrame: proposedFrame
        )
    }

    private func moveValidated(
        _ element: any WindowMovableElement,
        snap: WindowSnapshot,
        action: WindowAction,
        originalFrame: CGRect,
        proposedFrame: CGRect
    ) -> WindowMovementResult {
        let sizeChanges = !approximatelyEqual(originalFrame.size, proposedFrame.size)
        guard !sizeChanges || snap.isResizable else {
            return result(
                action: action,
                status: .fixedSizeWindow,
                originalFrame: originalFrame,
                proposedFrame: proposedFrame,
                element: element
            )
        }

        var enhancedUserInterfaceWriteSucceeded = true
        let previousEnhancedUserInterface = snap.enhancedUserInterfaceEnabled
        if previousEnhancedUserInterface != nil {
            enhancedUserInterfaceWriteSucceeded = element.setEnhancedUserInterfaceEnabled(false)
        }

        let writeSignpost = PerformanceSignpost.WindowControl.beginAXWrite()
        if animationConfiguration.shouldAnimate {
            if let previousEnhancedUserInterface {
                savedEnhancedUserInterface = (element: element, value: previousEnhancedUserInterface)
            }
            applyAnimatedMoveNonBlocking(
                element: element,
                snap: snap,
                from: originalFrame,
                to: proposedFrame
            ) { [self] in
                PerformanceSignpost.WindowControl.endAXWrite(writeSignpost)
                savedEnhancedUserInterface = nil
                clampOffscreenWindow(element)
                retryCrossDisplaySizeIfNeeded(
                    element: element,
                    snap: snap,
                    proposedFrame: proposedFrame,
                    originalFrame: originalFrame,
                    action: action
                )
                if let previousEnhancedUserInterface {
                    _ = element.setEnhancedUserInterfaceEnabled(previousEnhancedUserInterface)
                }
            }
        } else {
            applyInstantFrameWrite(element: element, snap: snap, proposedFrame: proposedFrame)
            clampOffscreenWindow(element)
            retryCrossDisplaySizeIfNeeded(
                element: element,
                snap: snap,
                proposedFrame: proposedFrame,
                originalFrame: originalFrame,
                action: action
            )
            if let previousEnhancedUserInterface {
                enhancedUserInterfaceWriteSucceeded = element.setEnhancedUserInterfaceEnabled(previousEnhancedUserInterface)
                    && enhancedUserInterfaceWriteSucceeded
            }
            PerformanceSignpost.WindowControl.endAXWrite(writeSignpost)
        }

        let actualFrame: CGRect
        let writeLandedSomewhereValid: Bool
        if animationConfiguration.shouldAnimate {
            actualFrame = proposedFrame
            writeLandedSomewhereValid = isValid(frame: actualFrame)
        } else {
            actualFrame = element.frame
            writeLandedSomewhereValid = isValid(frame: actualFrame)
        }

        return result(
            action: action,
            status: writeLandedSomewhereValid && enhancedUserInterfaceWriteSucceeded ? .moved : .writeFailed,
            originalFrame: originalFrame,
            proposedFrame: proposedFrame,
            element: element,
            resultingFrame: actualFrame
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
        guard repeatHalfAcrossDisplays,
              screenDetector.screens.count > 1,
              let previousResult,
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
        guard repeatHalfAcrossDisplays,
              screenDetector.screens.count > 1,
              let previousResult,
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
             .maximize, .almostMaximize, .center, .restore, .nextDisplay, .previousDisplay,
             .nextSpace, .previousSpace:
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
        element: any WindowMovableElement,
        resultingFrame: CGRect? = nil
    ) -> WindowMovementResult {
        WindowMovementResult(
            action: action,
            status: status,
            originalFrame: originalFrame,
            proposedFrame: proposedFrame,
            resultingFrame: resultingFrame ?? element.frame
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
        let snap = element.snapshot()
        let originalFrame = snap.frame
        guard snap.isSupportedForWindowControl, snap.isMovable, isValid(frame: originalFrame) else {
            return nil
        }
        return targetFrame(
            for: action,
            currentFrame: originalFrame,
            preserveSize: !snap.isResizable,
            previousResult: nil
        )
    }
}

private extension WindowMover {
    /// Always run every write regardless of individual return values. AX attribute-set
    /// return codes are unreliable for size/position — apps can accept a write but clamp
    /// the value silently, or reject a write whose effect actually takes hold.
    func applyInstantFrameWrite(
        element: any WindowMovableElement,
        snap: WindowSnapshot,
        proposedFrame: CGRect
    ) {
        if snap.isResizable {
            _ = element.setSize(proposedFrame.size)
            _ = element.setPosition(proposedFrame.origin)
            _ = element.setSize(proposedFrame.size)
        } else {
            _ = element.setPosition(proposedFrame.origin)
        }
    }

    func applyAnimatedMoveNonBlocking(
        element: any WindowMovableElement,
        snap: WindowSnapshot,
        from originalFrame: CGRect,
        to proposedFrame: CGRect,
        completion: @escaping () -> Void
    ) {
        // Cancel any previous timer only — savedEnhancedUserInterface is managed by moveValidated.
        moveAnimationGeneration += 1
        moveAnimationTimer?.invalidate()
        moveAnimationTimer = nil
        let config = animationConfiguration
        let steps = config.stepCount
        let interval = config.stepInterval
        guard interval > 0 else {
            applyInstantFrameWrite(element: element, snap: snap, proposedFrame: proposedFrame)
            completion()
            return
        }

        moveAnimationGeneration += 1
        let generation = moveAnimationGeneration
        var step = 0
        moveAnimationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self, generation == self.moveAnimationGeneration else {
                timer.invalidate()
                return
            }
            step += 1
            let progress = CGFloat(step) / CGFloat(steps)
            let interpolated = CGRect(
                x: originalFrame.origin.x + (proposedFrame.origin.x - originalFrame.origin.x) * progress,
                y: originalFrame.origin.y + (proposedFrame.origin.y - originalFrame.origin.y) * progress,
                width: originalFrame.width + (proposedFrame.width - originalFrame.width) * progress,
                height: originalFrame.height + (proposedFrame.height - originalFrame.height) * progress
            )
            if snap.isResizable {
                _ = element.setSize(interpolated.size)
            }
            _ = element.setPosition(interpolated.origin)
            if step >= steps {
                timer.invalidate()
                self.moveAnimationTimer = nil
                if snap.isResizable {
                    _ = element.setSize(proposedFrame.size)
                }
                _ = element.setPosition(proposedFrame.origin)
                if generation == self.moveAnimationGeneration {
                    completion()
                }
            }
        }
        if let moveAnimationTimer {
            RunLoop.main.add(moveAnimationTimer, forMode: .common)
        }
    }

    func retryCrossDisplaySizeIfNeeded(
        element: any WindowMovableElement,
        snap: WindowSnapshot,
        proposedFrame: CGRect,
        originalFrame: CGRect,
        action: WindowAction
    ) {
        guard WindowCrossDisplayRetry.isCrossDisplayMove(
            action: action,
            originalFrame: originalFrame,
            proposedFrame: proposedFrame,
            screenDetector: screenDetector
        ) else {
            return
        }

        guard WindowCrossDisplayRetry.needsSizeCorrection(
            actual: element.frame,
            proposed: proposedFrame
        ) else {
            return
        }

        applyInstantFrameWrite(element: element, snap: snap, proposedFrame: proposedFrame)

        guard WindowCrossDisplayRetry.needsSizeCorrection(
            actual: element.frame,
            proposed: proposedFrame
        ) else {
            return
        }

        scheduleCrossDisplayRetry { [self] in
            applyInstantFrameWrite(element: element, snap: snap, proposedFrame: proposedFrame)
        }
    }

    func scheduleCrossDisplayRetry(_ work: @escaping () -> Void) {
        pendingCrossDisplayRetry?.cancel()
        let item = DispatchWorkItem { [weak self] in
            work()
            self?.pendingCrossDisplayRetry = nil
        }
        pendingCrossDisplayRetry = item
        crossDisplayRetryScheduler { item.perform() }
    }

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
