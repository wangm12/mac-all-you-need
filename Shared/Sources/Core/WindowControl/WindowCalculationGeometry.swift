import CoreGraphics

enum WindowCalculationGeometry {
    static func centeredRect(size: CGSize, in frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX + (frame.width - size.width) / 2,
            y: frame.minY + (frame.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    static func clamped(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let clampedWidth = min(rect.width, bounds.width)
        let clampedHeight = min(rect.height, bounds.height)
        let maxX = bounds.maxX - clampedWidth
        let maxY = bounds.maxY - clampedHeight
        let clampedX = min(max(rect.origin.x, bounds.minX), maxX)
        let clampedY = min(max(rect.origin.y, bounds.minY), maxY)

        return CGRect(x: clampedX, y: clampedY, width: clampedWidth, height: clampedHeight)
    }
}
