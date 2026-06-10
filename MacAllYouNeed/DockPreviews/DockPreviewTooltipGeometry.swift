import CoreGraphics
import Foundation

/// Computes the opaque strip rect that covers the macOS Dock tooltip below a hovered icon.
enum DockPreviewTooltipGeometry {
    /// Typical Dock tooltip height above the icon when bottom-docked.
    static let defaultTooltipHeight: CGFloat = 28
    static let horizontalPadding: CGFloat = 8

    static func overlayRect(iconRect: CGRect, tooltipHeight: CGFloat = defaultTooltipHeight) -> CGRect {
        CGRect(
            x: iconRect.midX - iconRect.width / 2 - horizontalPadding,
            y: iconRect.minY - tooltipHeight,
            width: iconRect.width + horizontalPadding * 2,
            height: tooltipHeight
        )
    }
}
