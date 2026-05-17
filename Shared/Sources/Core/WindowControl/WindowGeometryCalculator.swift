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
        case .restore, .nextDisplay, .previousDisplay:
            return nil
        }
    }

    public func rectForMovingDisplay(
        currentFrame: CGRect,
        sourceVisibleFrame: CGRect,
        targetVisibleFrame: CGRect
    ) -> CGRect {
        guard sourceVisibleFrame.width > 0, sourceVisibleFrame.height > 0 else {
            return currentFrame.clamped(to: targetVisibleFrame)
        }

        let normalizedX = (currentFrame.minX - sourceVisibleFrame.minX) / sourceVisibleFrame.width
        let normalizedY = (currentFrame.minY - sourceVisibleFrame.minY) / sourceVisibleFrame.height
        let normalizedWidth = currentFrame.width / sourceVisibleFrame.width
        let normalizedHeight = currentFrame.height / sourceVisibleFrame.height

        let moved = CGRect(
            x: targetVisibleFrame.minX + normalizedX * targetVisibleFrame.width,
            y: targetVisibleFrame.minY + normalizedY * targetVisibleFrame.height,
            width: normalizedWidth * targetVisibleFrame.width,
            height: normalizedHeight * targetVisibleFrame.height
        )

        return moved.clamped(to: targetVisibleFrame)
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
