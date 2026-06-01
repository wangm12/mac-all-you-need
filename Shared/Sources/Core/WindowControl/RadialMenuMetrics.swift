import CoreGraphics
import Foundation

/// Layout constants shared by radial menu UI and cursor hit testing.
public enum RadialMenuMetrics {
    public static let menuRadius: CGFloat = 100
    public static let panelPadding: CGFloat = 10
    /// Gap between the close pill and the radial ring along the pill orbit ray.
    public static let closePillGapFromCircle: CGFloat = 3
    /// Close pill sits on this ray from the menu center (SwiftUI coords, +Y down): up-left at 45°.
    private static let closePillDiagonalFactor: CGFloat = 0.707_106_781_186_547_6

    public static var panelDimension: CGFloat { panelSize(for: menuRadius).height }

    /// Center hub diameter as a fraction of the menu diameter.
    public static let centerButtonRadiusRatio: CGFloat = 0.25
    /// Ring icon placement as a fraction of menu radius (lower = more inset from the outer ring).
    public static let ringIconRadiusRatio: CGFloat = 0.64

    /// Radius of the center maximize affordance in `RadialMenuView` (`centerDiameter / 2`).
    public static var centerButtonRadius: CGFloat { centerButtonRadius(for: menuRadius) }
    /// Cursor hit radius for center / maximize — matches the visible center button plus a small pad.
    public static var centerSelectionRadius: CGFloat { centerButtonRadius(for: menuRadius) + 6 }
    /// Ring segment icons are placed at this radius from the menu center.
    public static var ringIconRadius: CGFloat { ringIconRadius(for: menuRadius) }

    public static func centerButtonRadius(for menuRadius: CGFloat) -> CGFloat {
        menuRadius * centerButtonRadiusRatio
    }

    public static func ringIconRadius(for menuRadius: CGFloat) -> CGFloat {
        menuRadius * ringIconRadiusRatio
    }

    public static func panelPadding(for menuRadius: CGFloat) -> CGFloat {
        panelPadding * (menuRadius / Self.menuRadius)
    }

    public static func closePillGapFromCircle(for menuRadius: CGFloat) -> CGFloat {
        closePillGapFromCircle * (menuRadius / Self.menuRadius)
    }

    /// Distance from menu center to close-pill center along the top-left 45° ray.
    public static func closePillOrbitDistance(for menuRadius: CGFloat) -> CGFloat {
        let gap = closePillGapFromCircle(for: menuRadius)
        let halfWidth = closePillSize.width / 2
        let halfHeight = closePillSize.height / 2
        let innerReach = (halfWidth + halfHeight) * closePillDiagonalFactor
        return menuRadius + gap + innerReach
    }

    /// Offset from menu-circle center to close-pill center (SwiftUI coords, +Y down).
    public static func closePillOffsetFromCircleCenter(for menuRadius: CGFloat) -> CGPoint {
        let orbit = closePillOrbitDistance(for: menuRadius)
        return CGPoint(
            x: -orbit * closePillDiagonalFactor,
            y: -orbit * closePillDiagonalFactor
        )
    }

    public struct PanelLayout: Equatable {
        public let size: CGSize
        public let circleCenter: CGPoint
        public let closePillOrigin: CGPoint
    }

    public static func panelLayout(for menuRadius: CGFloat, showsClosePill: Bool = true) -> PanelLayout {
        let pad = panelPadding(for: menuRadius)
        if showsClosePill {
            let pillOffset = closePillOffsetFromCircleCenter(for: menuRadius)
            let halfWidth = closePillSize.width / 2
            let halfHeight = closePillSize.height / 2

            let contentMinX = min(-menuRadius, pillOffset.x - halfWidth)
            let contentMaxX = max(menuRadius, pillOffset.x + halfWidth)
            let contentMinY = min(-menuRadius, pillOffset.y - halfHeight)
            let contentMaxY = max(menuRadius, pillOffset.y + halfHeight)

            let width = contentMaxX - contentMinX + pad * 2
            let height = contentMaxY - contentMinY + pad * 2
            let circleCenter = CGPoint(x: pad - contentMinX, y: pad - contentMinY)
            let closePillOrigin = CGPoint(
                x: circleCenter.x + pillOffset.x - halfWidth,
                y: circleCenter.y + pillOffset.y - halfHeight
            )
            return PanelLayout(
                size: CGSize(width: width, height: height),
                circleCenter: circleCenter,
                closePillOrigin: closePillOrigin
            )
        }
        let dimension = menuRadius * 2 + pad * 2
        let center = CGPoint(x: dimension / 2, y: dimension / 2)
        return PanelLayout(
            size: CGSize(width: dimension, height: dimension),
            circleCenter: center,
            closePillOrigin: CGPoint(x: pad, y: pad)
        )
    }

    public static func panelSize(for menuRadius: CGFloat, showsClosePill: Bool = true) -> CGSize {
        panelLayout(for: menuRadius, showsClosePill: showsClosePill).size
    }

    /// Menu-circle center within the hosting panel (SwiftUI coords, +Y down).
    public static func circleCenterInPanel(for menuRadius: CGFloat, showsClosePill: Bool = true) -> CGPoint {
        panelLayout(for: menuRadius, showsClosePill: showsClosePill).circleCenter
    }

    public static func panelDimension(for menuRadius: CGFloat) -> CGFloat {
        panelSize(for: menuRadius).height
    }

    /// Circle-center distance from the panel bottom in AppKit coordinates (+Y up).
    public static func circleCenterYFromPanelBottom(for menuRadius: CGFloat, showsClosePill: Bool = true) -> CGFloat {
        let layout = panelLayout(for: menuRadius, showsClosePill: showsClosePill)
        return layout.size.height - layout.circleCenter.y
    }

    /// AppKit bottom-left origin for a panel whose circle center sits at `menuCenterAppKit`.
    public static func panelOriginAppKit(
        menuCenter: CGPoint,
        menuRadius: CGFloat = menuRadius,
        showsClosePill: Bool = true
    ) -> CGPoint {
        let layout = panelLayout(for: menuRadius, showsClosePill: showsClosePill)
        return CGPoint(
            x: menuCenter.x - layout.circleCenter.x,
            y: menuCenter.y - circleCenterYFromPanelBottom(for: menuRadius, showsClosePill: showsClosePill)
        )
    }

    /// Hit target for the top-leading close pill; keep in sync with `RadialMenuView.closePill`.
    public static let closePillSize = CGSize(width: 56, height: 40)

    /// Close-pill center offset from menu center (CG display coords, +Y down).
    public static var closePillCenterOffset: CGPoint {
        closePillCenterOffset(for: menuRadius)
    }

    public static func closePillCenterOffset(for menuRadius: CGFloat) -> CGPoint {
        let layout = panelLayout(for: menuRadius, showsClosePill: true)
        let pillCenter = CGPoint(
            x: layout.closePillOrigin.x + closePillSize.width / 2,
            y: layout.closePillOrigin.y + closePillSize.height / 2
        )
        return CGPoint(
            x: pillCenter.x - layout.circleCenter.x,
            y: pillCenter.y - layout.circleCenter.y
        )
    }

    public static func closePillRect(menuCenter: CGPoint) -> CGRect {
        closePillRect(menuCenter: menuCenter, menuRadius: menuRadius)
    }

    public static func closePillRect(menuCenter: CGPoint, menuRadius: CGFloat) -> CGRect {
        let offset = closePillCenterOffset(for: menuRadius)
        return CGRect(
            x: menuCenter.x + offset.x - closePillSize.width / 2,
            y: menuCenter.y + offset.y - closePillSize.height / 2,
            width: closePillSize.width,
            height: closePillSize.height
        )
    }
}
