import CoreGraphics
import Foundation

/// Pure cursor angle/distance to puck HUD selection math.
/// No AppKit, no UI imports — fully testable.
public enum RadialSelectionMath {
    public static let ringCount = RadialPuckMetrics.ringCount

    public enum Selection: Equatable, Hashable {
        case none
        case ring(Int)
        case fullScreen
    }

    /// Stateful hysteresis for stable selection near boundaries.
    public struct SelectionState: Equatable {
        public var isArmed: Bool
        public var lastRingIndex: Int?
        public var isFullScreen: Bool
        /// Monotonic clock time when the cursor first crossed `fullScreenEnterDistance`.
        public var fullScreenArmingStartedAt: TimeInterval?

        public init(
            isArmed: Bool = false,
            lastRingIndex: Int? = nil,
            isFullScreen: Bool = false,
            fullScreenArmingStartedAt: TimeInterval? = nil
        ) {
            self.isArmed = isArmed
            self.lastRingIndex = lastRingIndex
            self.isFullScreen = isFullScreen
            self.fullScreenArmingStartedAt = fullScreenArmingStartedAt
        }
    }

    public static func action(for selection: Selection) -> WindowAction? {
        switch selection {
        case .none:
            nil
        case let .ring(index):
            RadialMenuLayout.action(forRingIndex: index)
        case .fullScreen:
            RadialMenuLayout.fillScreenAction
        }
    }

    /// `delta` is `cursor - menuCenter` in CG display coordinates (+Y down).
    /// Pass `now` (monotonic seconds, e.g. `ProcessInfo.processInfo.systemUptime`) to apply
    /// Fill Screen dwell; omit for instantaneous distance-only behavior (tests).
    public static func selection(
        from delta: CGPoint,
        state: inout SelectionState,
        now: TimeInterval? = nil
    ) -> Selection {
        let distance = hypot(delta.x, delta.y)

        if state.isArmed {
            if distance < RadialPuckMetrics.armedExitDistance {
                state = SelectionState()
                return .none
            }
        } else if distance < RadialPuckMetrics.armedEnterDistance {
            return .none
        } else {
            state.isArmed = true
        }

        let rawRingIndex = rawRingIndex(from: delta)
        let ringIndex = applyAngleHysteresis(
            rawIndex: rawRingIndex,
            lastIndex: state.lastRingIndex,
            delta: delta
        )
        state.lastRingIndex = ringIndex

        if state.isFullScreen {
            if distance < RadialPuckMetrics.fullScreenExitDistance {
                state.isFullScreen = false
                state.fullScreenArmingStartedAt = nil
                return .ring(ringIndex)
            }
            return .fullScreen
        }

        if distance >= RadialPuckMetrics.fullScreenEnterDistance {
            if let now {
                if state.fullScreenArmingStartedAt == nil {
                    state.fullScreenArmingStartedAt = now
                }
                if now - (state.fullScreenArmingStartedAt ?? now) < RadialPuckMetrics.fullScreenEnterDwell {
                    state.isFullScreen = false
                    return .ring(ringIndex)
                }
            }
            state.isFullScreen = true
            state.fullScreenArmingStartedAt = nil
            return .fullScreen
        }

        state.fullScreenArmingStartedAt = nil
        state.isFullScreen = false
        return .ring(ringIndex)
    }

    /// Distance from anchor for rendering the active puck along the aim ray.
    public static func displayDistance(for delta: CGPoint, selection: Selection) -> CGFloat {
        let distance = hypot(delta.x, delta.y)
        if distance >= RadialPuckMetrics.fullScreenExitDistance {
            return min(
                max(distance, RadialPuckMetrics.armedEnterDistance),
                RadialPuckMetrics.fullScreenRayMaxRadius
            )
        }
        switch selection {
        case .none:
            return 0
        case .fullScreen:
            return min(
                max(distance, RadialPuckMetrics.armedEnterDistance),
                RadialPuckMetrics.fullScreenRayMaxRadius
            )
        case .ring:
            return min(max(distance, RadialPuckMetrics.armedEnterDistance), RadialPuckMetrics.guideRingRadius)
        }
    }

    /// Whether the puck HUD should track live cursor aim instead of canonical ring angles.
    public static func usesCursorAim(for delta: CGPoint, selection: Selection) -> Bool {
        if selection == .fullScreen { return true }
        return hypot(delta.x, delta.y) >= RadialPuckMetrics.fullScreenExitDistance
    }

    public static func aimAngleRadians(for delta: CGPoint) -> CGFloat {
        let angle = atan2(delta.x, -delta.y)
        return angle < 0 ? angle + 2 * .pi : angle
    }

    public static func aimAngleRadians(forRingIndex index: Int) -> CGFloat {
        RadialMenuLayout.canonicalAngleRadians(forRingIndex: index)
    }

    public static func syntheticDelta(
        for selection: Selection,
        distance: CGFloat = RadialPuckMetrics.keyboardRingDistance
    ) -> CGPoint {
        switch selection {
        case .none:
            return .zero
        case .fullScreen:
            return CGPoint(x: 0, y: -distance)
        case let .ring(index):
            let angle = RadialMenuLayout.canonicalAngleRadians(forRingIndex: index)
            return CGPoint(x: sin(angle) * distance, y: -cos(angle) * distance)
        }
    }

    private static func rawRingIndex(from delta: CGPoint) -> Int {
        let angle = aimAngleRadians(for: delta)
        let segmentWidth = 2 * CGFloat.pi / CGFloat(ringCount)
        let shifted = (angle + segmentWidth / 2).truncatingRemainder(dividingBy: 2 * .pi)
        return Int(shifted / segmentWidth) % ringCount
    }

    private static func applyAngleHysteresis(rawIndex: Int, lastIndex: Int?, delta: CGPoint) -> Int {
        guard let lastIndex else { return rawIndex }
        if rawIndex == lastIndex { return lastIndex }

        let angle = aimAngleRadians(for: delta)
        let segmentWidth = 2 * CGFloat.pi / CGFloat(ringCount)
        let lastCenter = CGFloat(lastIndex) * segmentWidth
        var diff = angle - lastCenter
        while diff > .pi { diff -= 2 * .pi }
        while diff < -.pi { diff += 2 * .pi }

        let halfSegment = segmentWidth / 2
        if abs(diff) < halfSegment + RadialPuckMetrics.angleHysteresisRadians {
            return lastIndex
        }
        return rawIndex
    }

    /// Compensates for macOS cursor pinning at the **desktop** perimeter while the radial menu is open.
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
            let maxOffset = RadialPuckMetrics.armedEnterDistance + RadialPuckMetrics.guideRingRadius

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
            }
            if atMinY || atMaxY {
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
