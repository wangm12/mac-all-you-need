import CoreGraphics
import Foundation

/// Layout and gesture thresholds for the Radial Puck HUD.
public enum RadialPuckMetrics {
    public static let armedEnterDistance: CGFloat = 30
    public static let armedExitDistance: CGFloat = 24
    public static let guideRingRadius: CGFloat = 55
    /// Pull distance before Fill Screen arms (well beyond the ring band at `guideRingRadius`).
    public static let fullScreenEnterDistance: CGFloat = 130
    public static let fullScreenExitDistance: CGFloat = 115
    public static let fullScreenRayMaxRadius: CGFloat = 88
    /// Seconds the cursor must stay past `fullScreenEnterDistance` before Fill Screen arms.
    public static let fullScreenEnterDwell: TimeInterval = 0.18
    public static let ambientPuckRadius: CGFloat = 38
    public static let activePuckRadius: CGFloat = 16
    public static let activePuckFullScreenBoost: CGFloat = 1.5
    public static let centerDotRadius: CGFloat = 3.2
    public static let centerSafeRingRadius: CGFloat = 18
    public static let labelOffsetY: CGFloat = 76
    public static let labelPillHeight: CGFloat = 28
    public static let chevronArmSpan: CGFloat = 7
    public static let chevronTopY: CGFloat = 82
    public static let chevronApexY: CGFloat = 90
    public static let angleHysteresisDegrees: CGFloat = 7
    public static var angleHysteresisRadians: CGFloat { angleHysteresisDegrees * .pi / 180 }
    public static let panelPadding: CGFloat = 12
    public static let ringCount = 8

    /// Radius used when keyboard selection arms a ring action.
    public static let keyboardRingDistance: CGFloat = guideRingRadius

    public static var panelHalfExtent: CGFloat {
        max(fullScreenRayMaxRadius, chevronApexY) + labelOffsetY + labelPillHeight / 2 + panelPadding
    }

    public static var panelSize: CGSize {
        let extent = panelHalfExtent * 2
        return CGSize(width: extent, height: extent)
    }

    public static var circleCenterInPanel: CGPoint {
        CGPoint(x: panelHalfExtent, y: panelHalfExtent)
    }

    public static func panelOriginAppKit(menuCenter: CGPoint) -> CGPoint {
        let center = circleCenterInPanel
        return CGPoint(x: menuCenter.x - center.x, y: menuCenter.y - (panelSize.height - center.y))
    }

    /// Maps canonical aim angle (0 = up, clockwise) to panel offset from the puck center.
    public static func activePuckOffset(angle: CGFloat, radius: CGFloat) -> CGPoint {
        CGPoint(x: sin(angle) * radius, y: -cos(angle) * radius)
    }

    /// Active puck position in panel coordinates for a canonical ring index.
    public static func activePuckCenter(forRingIndex index: Int, radius: CGFloat) -> CGPoint {
        let center = circleCenterInPanel
        let angle = RadialMenuLayout.canonicalAngleRadians(forRingIndex: index)
        let offset = activePuckOffset(angle: angle, radius: radius)
        return CGPoint(x: center.x + offset.x, y: center.y + offset.y)
    }
}
