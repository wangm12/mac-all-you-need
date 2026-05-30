import CoreGraphics
import Foundation

/// Pure cursor angle/distance to ring-index selection math.
/// No AppKit, no UI imports — fully testable.
public enum RadialSelectionMath {
    public static let centerBandRadius: CGFloat = 40.0
    public static let ringCount = 8

    /// Result of mapping a center-to-cursor vector onto the radial menu.
    /// - `.center` if within the center band
    /// - `.ring(index)` for the outer ring (0 = top, clockwise)
    /// - `.none` if the cursor has not moved far enough to commit
    public enum Selection: Equatable, Hashable {
        case none
        case center
        case ring(Int)
    }

    /// Inputs are in CG display coordinates where +Y points down (matching
    /// `CGEvent.location`). `delta` is `cursor - menuCenter`.
    public static func selection(from delta: CGPoint, activationDistance: CGFloat = 30.0) -> Selection {
        let distance = sqrt(delta.x * delta.x + delta.y * delta.y)
        guard distance >= activationDistance else { return .none }
        if distance < centerBandRadius { return .center }

        // Angle measured from the top (up), increasing clockwise. In CG coords
        // up is -Y, so negate the Y component before atan2.
        let angle = atan2(delta.x, -delta.y)
        let normalized = angle < 0 ? angle + 2 * .pi : angle
        let segmentWidth = 2 * CGFloat.pi / CGFloat(ringCount)
        // Offset by half a segment so each ring action is centered on its
        // cardinal/diagonal direction rather than starting at it.
        let shifted = (normalized + segmentWidth / 2).truncatingRemainder(dividingBy: 2 * .pi)
        let segment = Int(shifted / segmentWidth) % ringCount
        return .ring(segment)
    }
}
