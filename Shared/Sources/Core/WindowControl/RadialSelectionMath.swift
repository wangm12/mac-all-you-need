import CoreGraphics
import Foundation

/// Pure cursor angle/distance to ring-index selection math.
/// No AppKit, no UI imports — fully testable.
public enum RadialSelectionMath {
    /// Minimum cursor travel from menu center before a ring segment is selected.
    public static let activationDistance: CGFloat = 12
    /// Inside this radius selects the center maximize action (matches the visible center button).
    /// The center band is exempt from `activationDistance` so the icon hub arms on hover, not only
    /// the annulus between the dead zone and the button edge.
    public static var centerBandRadius: CGFloat { RadialMenuMetrics.centerSelectionRadius }
    public static let ringCount = 8

    /// Result of mapping a center-to-cursor vector onto the radial menu.
    /// - `.center` if within the center band
    /// - `.ring(index)` for the outer ring (0 = top, clockwise)
    /// - `.none` if the cursor has not moved far enough to arm a ring segment
    public enum Selection: Equatable, Hashable {
        case none
        case center
        case ring(Int)
        /// Cursor is over the top-leading close pill; dismiss without applying a layout.
        case cancel
    }

    /// Whether `cursor` is inside the close pill for a menu centered at `menuCenter`.
    public static func closeZoneContains(cursor: CGPoint, menuCenter: CGPoint) -> Bool {
        RadialMenuMetrics.closePillRect(menuCenter: menuCenter).contains(cursor)
    }

    /// Inputs are in CG display coordinates where +Y points down (matching
    /// `CGEvent.location`). `delta` is `cursor - menuCenter`.
    public static func selection(
        from delta: CGPoint,
        cursor: CGPoint? = nil,
        menuCenter: CGPoint? = nil,
        activationDistance: CGFloat = RadialSelectionMath.activationDistance
    ) -> Selection {
        if let cursor, let menuCenter, closeZoneContains(cursor: cursor, menuCenter: menuCenter) {
            return .cancel
        }
        let distance = sqrt(delta.x * delta.x + delta.y * delta.y)
        if distance < centerBandRadius { return .center }
        guard distance >= activationDistance else { return .none }

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

    /// Compensates for macOS cursor pinning at the **desktop** perimeter while the radial menu is open.
    ///
    /// Uses `desktopBounds` (union of all displays) so inter-monitor edges are not treated as
    /// pinned edges — that mismatch caused the cursor to appear stuck or loop on one screen
    /// when multiple monitors were attached.
    public struct EdgeClamp {
        private var latest: CGPoint
        private let desktopBounds: CGRect
        private let shouldAccountForAbsolute: Bool

        public init(initial: CGPoint, desktopBounds: CGRect) {
            latest = initial
            self.desktopBounds = desktopBounds
            let threshold: CGFloat = 5
            shouldAccountForAbsolute =
                initial.x <= desktopBounds.minX + threshold
                || initial.x >= desktopBounds.maxX - threshold
                || initial.y <= desktopBounds.minY + threshold
                || initial.y >= desktopBounds.maxY - threshold
        }

        public mutating func resolve(current: CGPoint, deltaX: CGFloat, deltaY: CGFloat) -> CGPoint {
            guard shouldAccountForAbsolute else {
                latest = current
                return latest
            }

            let edgeThreshold: CGFloat = 1
            let maxOffset = RadialSelectionMath.activationDistance + RadialSelectionMath.centerBandRadius

            let atMinX = abs(current.x - desktopBounds.minX) < edgeThreshold
            let atMaxX = abs(current.x - desktopBounds.maxX) < edgeThreshold
            let atMinY = abs(current.y - desktopBounds.minY) < edgeThreshold
            let atMaxY = abs(current.y - desktopBounds.maxY) < edgeThreshold

            var resolved = current

            if atMinX || atMaxX {
                let unclampedX = latest.x + deltaX
                let minX = desktopBounds.minX - maxOffset
                let maxX = desktopBounds.maxX + maxOffset
                resolved.x = min(max(unclampedX, minX), maxX)
            } else if atMinY || atMaxY {
                let unclampedY = latest.y + deltaY
                let minY = desktopBounds.minY - maxOffset
                let maxY = desktopBounds.maxY + maxOffset
                resolved.y = min(max(unclampedY, minY), maxY)
            }

            latest = resolved
            return latest
        }
    }
}
