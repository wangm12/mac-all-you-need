import CoreGraphics
import Foundation

/// Pure geometry calculations for panel placement near the Dock icon.
enum DockPreviewPanelGeometry {
    enum DockEdge { case bottom, left, right }

    /// Converts a Quartz coordinate (origin bottom-left) to Cocoa screen coordinate.
    static func cocoaRect(fromQuartz quartzRect: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(
            x: quartzRect.origin.x,
            y: screenHeight - quartzRect.origin.y - quartzRect.height,
            width: quartzRect.width,
            height: quartzRect.height
        )
    }

    /// Given the Dock icon position and panel size, returns the panel origin (Cocoa coords).
    static func panelOrigin(iconRect: CGRect, panelSize: CGSize, screenBounds: CGRect, dockEdge: DockEdge) -> CGPoint {
        var x: CGFloat
        var y: CGFloat
        switch dockEdge {
        case .bottom:
            x = iconRect.midX - panelSize.width / 2
            y = iconRect.maxY + 8
        case .left:
            x = iconRect.maxX + 8
            y = iconRect.midY - panelSize.height / 2
        case .right:
            x = iconRect.minX - panelSize.width - 8
            y = iconRect.midY - panelSize.height / 2
        }
        // Clamp to screen bounds
        x = max(screenBounds.minX, min(x, screenBounds.maxX - panelSize.width))
        y = max(screenBounds.minY, min(y, screenBounds.maxY - panelSize.height))
        return CGPoint(x: x, y: y)
    }
}
