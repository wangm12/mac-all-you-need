import Core
import CoreGraphics

extension CGRect {
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

extension WindowAction {
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
