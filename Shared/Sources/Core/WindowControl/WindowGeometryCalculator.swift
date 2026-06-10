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
        let halfWidth = visibleFrame.width / 2
        let halfHeight = visibleFrame.height / 2

        switch action {
        case .leftHalf:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: halfWidth, height: visibleFrame.height)
        case .rightHalf:
            return CGRect(x: visibleFrame.midX, y: visibleFrame.minY, width: halfWidth, height: visibleFrame.height)
        case .topHalf:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: visibleFrame.width, height: halfHeight)
        case .bottomHalf:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.midY, width: visibleFrame.width, height: halfHeight)
        case .topLeft:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: halfWidth, height: halfHeight)
        case .topRight:
            return CGRect(x: visibleFrame.midX, y: visibleFrame.minY, width: halfWidth, height: halfHeight)
        case .bottomLeft:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.midY, width: halfWidth, height: halfHeight)
        case .bottomRight:
            return CGRect(x: visibleFrame.midX, y: visibleFrame.midY, width: halfWidth, height: halfHeight)
        case .maximize:
            return visibleFrame
        case .almostMaximize:
            let size = CGSize(width: visibleFrame.width * 0.9, height: visibleFrame.height * 0.9)
            return centeredRect(size: size, in: visibleFrame)
        case .center:
            guard let currentSize else {
                return nil
            }
            return centeredRect(size: currentSize, in: visibleFrame)
        case .restore, .nextDisplay, .previousDisplay, .nextSpace, .previousSpace:
            return nil
        }
    }

    public func rectForMovingDisplay(
        currentFrame: CGRect,
        sourceVisibleFrame: CGRect,
        targetVisibleFrame: CGRect
    ) -> CGRect {
        // Preserve the window's size and keep its top-left offset relative to
        // the display's top-left corner. The previous ratio-scaling logic
        // shrunk Chrome / Slack / Office windows whenever the target display
        // was smaller in either axis, even when the window would have fit.
        // Falling back to clamped() at the end still shrinks size only when
        // the window is genuinely larger than the target visible frame.
        let offsetX = currentFrame.minX - sourceVisibleFrame.minX
        let offsetY = currentFrame.minY - sourceVisibleFrame.minY

        let translated = CGRect(
            x: targetVisibleFrame.minX + offsetX,
            y: targetVisibleFrame.minY + offsetY,
            width: currentFrame.width,
            height: currentFrame.height
        )

        return translated.clamped(to: targetVisibleFrame)
    }

    private func centeredRect(size: CGSize, in frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX + (frame.width - size.width) / 2,
            y: frame.minY + (frame.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}

private extension CGRect {
    func clamped(to bounds: CGRect) -> CGRect {
        let clampedWidth = min(width, bounds.width)
        let clampedHeight = min(height, bounds.height)
        let maxX = bounds.maxX - clampedWidth
        let maxY = bounds.maxY - clampedHeight
        let clampedX = min(max(origin.x, bounds.minX), maxX)
        let clampedY = min(max(origin.y, bounds.minY), maxY)

        return CGRect(x: clampedX, y: clampedY, width: clampedWidth, height: clampedHeight)
    }
}
