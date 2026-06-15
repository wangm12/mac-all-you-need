import CoreGraphics

/// Pure window geometry in AX/CG display coordinates.
///
/// Inputs are expected to match `CGEvent.location`, `CGWindow` bounds, and AX
/// window frames: `minY` is the top edge, `maxY` is the bottom edge, and Y
/// values increase downward.
public struct WindowGeometryCalculator: Sendable {
    public init() {}

    public func rect(
        for action: WindowAction,
        visibleFrame: CGRect,
        currentSize: CGSize? = nil
    ) -> CGRect? {
        WindowCalculationFactory.rect(for: action, visibleFrame: visibleFrame, currentSize: currentSize)
    }

    public func rectForMovingDisplay(
        currentFrame: CGRect,
        sourceVisibleFrame: CGRect,
        targetVisibleFrame: CGRect
    ) -> CGRect {
        WindowCalculationFactory.rectForMovingDisplay(
            currentFrame: currentFrame,
            sourceVisibleFrame: sourceVisibleFrame,
            targetVisibleFrame: targetVisibleFrame
        )
    }
}
