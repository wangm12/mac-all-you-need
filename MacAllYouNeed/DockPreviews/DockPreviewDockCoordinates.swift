import AppKit
import CoreGraphics
import Foundation
import Platform

// MARK: - Screen geometry (multi-monitor)

extension NSScreen {
    /// Screen frame in CG global coordinates (origin top-left, Y increases downward).
    var cgFrame: CGRect {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return frame }
        return CGRect(
            x: frame.minX,
            y: primaryHeight - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    /// Resolve the screen containing a point in AX / Quartz (top-left origin) space.
    static func screenFromQuartzPoint(_ point: CGPoint) -> NSScreen? {
        guard let primary = NSScreen.screens.first else { return nil }
        let appKitPoint = CGPoint(x: point.x, y: primary.frame.maxY - point.y)
        return NSScreen.screens.first { $0.frame.contains(appKitPoint) } ?? NSScreen.main ?? primary
    }
}

/// Dock icon and preview placement math aligned with DockDoor (`DockObserver` + `SharedPreviewWindowCoordinator`).
enum DockPreviewDockCoordinates {
    // MARK: - Screen offsets (DockDoor `DockObserver.computeOffsets`)

    private static func computeOffsets(
        for screen: NSScreen,
        primaryScreen: NSScreen
    ) -> (offsetLeft: CGFloat, offsetTop: CGFloat) {
        var offsetLeft = screen.frame.origin.x
        var offsetTop = primaryScreen.frame.size.height - (screen.frame.origin.y + screen.frame.size.height)

        if screen == primaryScreen {
            offsetTop = 0
            offsetLeft = 0
        }

        return (offsetLeft, offsetTop)
    }

    /// DockDoor `cgPointFromNSPoint` — converts AX/global screen point to preview placement space.
    static func placementPoint(fromAXPoint point: CGPoint, screen: NSScreen) -> CGPoint {
        guard let primaryScreen = NSScreen.screens.first else {
            return point
        }

        let (_, offsetTop) = computeOffsets(for: screen, primaryScreen: primaryScreen)
        let menuScreenHeight = screen.frame.maxY

        return CGPoint(x: point.x, y: menuScreenHeight - point.y + offsetTop)
    }

    static func flippedIconRect(axRect: CGRect, screen: NSScreen) -> CGRect {
        CGRect(
            origin: placementPoint(fromAXPoint: axRect.origin, screen: screen),
            size: axRect.size
        )
    }

    static func screen(containingAXPoint point: CGPoint) -> NSScreen? {
        NSScreen.screenFromQuartzPoint(point)
    }

    static func cgPoint(fromAppKit point: CGPoint) -> CGPoint {
        WindowScreenDetector.cgPoint(fromAppKit: point)
    }

    /// DockDoor `SharedPreviewWindowCoordinator.calculateWindowPosition` (Cocoa panel origin).
    static func previewPanelOrigin(
        axIconRect: CGRect,
        panelSize: CGSize,
        screen: NSScreen,
        dockEdge: DockPreviewPanelGeometry.DockEdge,
        bufferFromDock: CGFloat,
        anchoredIconRect: CGRect? = nil,
        isCmdTab: Bool = false
    ) -> CGPoint {
        let screenFrame = screen.frame
        let iconRect = anchoredIconRect ?? axIconRect
        let flippedIconRect = flippedIconRect(axRect: iconRect, screen: screen)

        var xPosition: CGFloat
        var yPosition: CGFloat

        switch dockEdge {
        case .bottom:
            xPosition = flippedIconRect.midX - panelSize.width / 2
            yPosition = flippedIconRect.minY
        case .left:
            xPosition = flippedIconRect.maxX
            yPosition = flippedIconRect.midY - panelSize.height / 2 - flippedIconRect.height
        case .right:
            xPosition = screenFrame.maxX - flippedIconRect.width - panelSize.width
            yPosition = flippedIconRect.minY - panelSize.height / 2
        }

        if isCmdTab {
            yPosition += 5
        } else {
            switch dockEdge {
            case .left:
                xPosition += bufferFromDock
            case .right:
                xPosition -= bufferFromDock
            case .bottom:
                yPosition += bufferFromDock
            }
        }

        xPosition = max(screenFrame.minX, min(xPosition, screenFrame.maxX - panelSize.width))
        yPosition = max(screenFrame.minY, min(yPosition, screenFrame.maxY - panelSize.height))

        return CGPoint(x: xPosition, y: yPosition)
    }

    /// Cocoa rect for hit-testing / bridge geometry from an AX dock item frame.
    static func cocoaIconRect(axRect: CGRect, screen: NSScreen) -> CGRect {
        let flipped = flippedIconRect(axRect: axRect, screen: screen)
        return CGRect(
            x: flipped.origin.x,
            y: flipped.minY - flipped.height,
            width: flipped.width,
            height: flipped.height
        )
    }
}
