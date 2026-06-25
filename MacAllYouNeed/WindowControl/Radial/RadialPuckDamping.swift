import CoreGraphics
import Foundation

enum RadialPuckDamping {
    static func damp(current: CGFloat, target: CGFloat, lambda: CGFloat, dt: CGFloat) -> CGFloat {
        guard dt > 0 else { return target }
        let t = 1 - exp(-lambda * dt)
        return current + (target - current) * t
    }

    static func normalizeAngle(_ angle: CGFloat) -> CGFloat {
        var normalized = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if normalized < 0 { normalized += 2 * .pi }
        return normalized
    }

    /// Signed shortest rotation from `from` to `to`, always in `(-π, π]`.
    static func shortestAngleDelta(from: CGFloat, to: CGFloat) -> CGFloat {
        atan2(sin(to - from), cos(to - from))
    }

    static func shortestAngle(from: CGFloat, to: CGFloat) -> CGFloat {
        from + shortestAngleDelta(from: from, to: to)
    }

    static func dampAngle(current: CGFloat, target: CGFloat, lambda: CGFloat, dt: CGFloat) -> CGFloat {
        let normalizedCurrent = normalizeAngle(current)
        let resolvedTarget = normalizedCurrent + shortestAngleDelta(from: normalizedCurrent, to: target)
        let damped = damp(current: normalizedCurrent, target: resolvedTarget, lambda: lambda, dt: dt)
        return normalizeAngle(damped)
    }

    static func dampRect(current: CGRect, target: CGRect, lambda: CGFloat, dt: CGFloat) -> CGRect {
        CGRect(
            x: damp(current: current.origin.x, target: target.origin.x, lambda: lambda, dt: dt),
            y: damp(current: current.origin.y, target: target.origin.y, lambda: lambda, dt: dt),
            width: damp(current: current.width, target: target.width, lambda: lambda, dt: dt),
            height: damp(current: current.height, target: target.height, lambda: lambda, dt: dt)
        )
    }
}
