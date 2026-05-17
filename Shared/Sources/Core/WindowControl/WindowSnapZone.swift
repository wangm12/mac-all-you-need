import CoreGraphics

/// Edge and corner snap zones in AX/CG display coordinates.
///
/// `minY` is the top edge, `maxY` is the bottom edge, and Y values increase downward.
public enum WindowSnapZone: String, CaseIterable, Codable, Sendable {
    case topLeft
    case top
    case topRight
    case left
    case right
    case bottomLeft
    case bottom
    case bottomRight
    case inside

    public var action: WindowAction? {
        switch self {
        case .topLeft:
            .topLeft
        case .top:
            .maximize
        case .topRight:
            .topRight
        case .left:
            .leftHalf
        case .right:
            .rightHalf
        case .bottomLeft:
            .bottomLeft
        case .bottom:
            .bottomHalf
        case .bottomRight:
            .bottomRight
        case .inside:
            nil
        }
    }

    public static func zone(
        for point: CGPoint,
        in visibleFrame: CGRect,
        edgeThreshold: CGFloat = 24,
        cornerThreshold: CGFloat = 96
    ) -> WindowSnapZone {
        let nearLeftEdge = point.x <= visibleFrame.minX + edgeThreshold
        let nearRightEdge = point.x >= visibleFrame.maxX - edgeThreshold
        let nearTopEdge = point.y <= visibleFrame.minY + edgeThreshold
        let nearBottomEdge = point.y >= visibleFrame.maxY - edgeThreshold

        let nearLeftCorner = point.x <= visibleFrame.minX + cornerThreshold
        let nearRightCorner = point.x >= visibleFrame.maxX - cornerThreshold
        let nearTopCorner = point.y <= visibleFrame.minY + cornerThreshold
        let nearBottomCorner = point.y >= visibleFrame.maxY - cornerThreshold

        if nearLeftCorner, nearTopCorner {
            return .topLeft
        }
        if nearRightCorner, nearTopCorner {
            return .topRight
        }
        if nearLeftCorner, nearBottomCorner {
            return .bottomLeft
        }
        if nearRightCorner, nearBottomCorner {
            return .bottomRight
        }
        if nearTopEdge {
            return .top
        }
        if nearLeftEdge {
            return .left
        }
        if nearRightEdge {
            return .right
        }
        if nearBottomEdge {
            return .bottom
        }
        return .inside
    }
}
