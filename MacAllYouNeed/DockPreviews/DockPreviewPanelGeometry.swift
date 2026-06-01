import AppKit
import CoreGraphics
import Foundation

/// Pure geometry calculations for panel placement near the Dock icon.
enum DockPreviewPanelGeometry {
    enum DockEdge { case bottom, left, right }

    /// AX dock item frame frozen for the hover session (DockDoor: `anchoredDockItem.iconRect`).
    static func frozenPlacementAnchor(axRect: CGRect) -> CGRect {
        guard axRect.width > 0, axRect.height > 0 else { return axRect }
        return axRect
    }

    /// Panel origin in Cocoa screen coordinates (DockDoor `calculateWindowPosition`).
    static func panelOrigin(
        axIconRect: CGRect,
        panelSize: CGSize,
        screen: NSScreen,
        dockEdge: DockEdge,
        bufferFromDock: CGFloat,
        anchoredIconRect: CGRect? = nil,
        isCmdTab: Bool = false
    ) -> CGPoint {
        DockPreviewDockCoordinates.previewPanelOrigin(
            axIconRect: axIconRect,
            panelSize: panelSize,
            screen: screen,
            dockEdge: dockEdge,
            bufferFromDock: bufferFromDock,
            anchoredIconRect: anchoredIconRect,
            isCmdTab: isCmdTab
        )
    }
}
