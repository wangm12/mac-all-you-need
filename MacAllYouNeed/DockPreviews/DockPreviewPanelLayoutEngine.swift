import AppKit
import SwiftUI

/// Panel frame measurement and animation (DockDoor `SharedPreviewWindowCoordinator` subset).
@MainActor
enum DockPreviewPanelLayoutEngine {
    struct LayoutInput: Equatable {
        var anchorRect: CGRect
        var anchoredIconRect: CGRect?
        var dockEdge: DockPreviewPanelGeometry.DockEdge
        var bufferFromDock: CGFloat
        var expectedContentSize: CGSize
        var showAnimations: Bool
        var centerOnScreen: Bool
        var isCmdTab: Bool = false
    }

    struct LayoutResult {
        var frame: CGRect
        var contentSize: CGSize
    }

    /// 1×1 measure trick then `fittingSize`, merged with `expectedContentSize`.
    static func measureAndLayout(
        panel: NSPanel,
        hostingView: NSHostingView<some View>,
        input: LayoutInput,
        previousFrame: CGRect?
    ) -> LayoutResult {
        let previousFrame = previousFrame ?? panel.frame
        panel.setFrame(
            CGRect(origin: previousFrame.origin, size: CGSize(width: 1, height: 1)),
            display: false
        )
        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize

        let screen: NSScreen = {
            if input.centerOnScreen {
                return NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
                    ?? NSScreen.main
                    ?? NSScreen.screens[0]
            }
            return DockPreviewDockCoordinates.screen(containingAXPoint: input.anchorRect.origin)
        }()

        let visible = screen.visibleFrame
        // DockDoor `updateContentViewSizeAndPosition`: max(fitting, expected), clamp to visible frame.
        let merged: CGSize
        if input.expectedContentSize == .zero {
            merged = fitting
        } else {
            merged = CGSize(
                width: max(fitting.width, input.expectedContentSize.width),
                height: max(fitting.height, input.expectedContentSize.height)
            )
        }
        let targetSize = CGSize(
            width: min(merged.width, visible.width),
            height: min(merged.height, visible.height)
        )

        let origin = panelOrigin(
            input: input,
            panelSize: targetSize,
            screen: screen
        )
        return LayoutResult(frame: CGRect(origin: origin, size: targetSize), contentSize: targetSize)
    }

    static func applyFrame(
        panel: NSPanel,
        target: CGRect,
        dockEdge: DockPreviewPanelGeometry.DockEdge,
        animated: Bool,
        isFirstShow: Bool
    ) {
        let shouldAnimate = animated
        if isFirstShow, shouldAnimate {
            let offset: CGFloat = 7 // DockDoor `applyWindowFrame` slide-in distance
            var start = target
            switch dockEdge {
            case .bottom: start.origin.y -= offset
            case .left: start.origin.x -= offset
            case .right: start.origin.x += offset
            }
            panel.alphaValue = 0
            panel.setFrame(start, display: true)
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.175
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(target, display: true)
                panel.animator().alphaValue = 1
            }
        } else if shouldAnimate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = MAYNMotionBridge.effectiveDuration(.hover)
                context.timingFunction = MAYNMotionBridge.timingFunction(.hover)
                panel.animator().setFrame(target, display: true)
            }
            panel.alphaValue = 1
        } else {
            panel.setFrame(target, display: true)
            panel.alphaValue = 1
        }
    }

    /// Resize while keeping the anchored edge fixed (DockDoor `refreshPanelFrameToFitContent`).
    static func resizedFrameKeepingAnchor(
        currentFrame: CGRect,
        newSize: CGSize,
        dockEdge: DockPreviewPanelGeometry.DockEdge,
        screen: NSScreen
    ) -> CGRect {
        let screenFrame = screen.visibleFrame
        var origin = currentFrame.origin
        switch dockEdge {
        case .bottom:
            origin.y = currentFrame.minY
            origin.x = currentFrame.midX - newSize.width / 2
        case .left:
            origin.x = currentFrame.minX
            origin.y = currentFrame.midY - newSize.height / 2
        case .right:
            origin.x = currentFrame.maxX - newSize.width
            origin.y = currentFrame.midY - newSize.height / 2
        }
        origin.x = max(screenFrame.minX, min(origin.x, screenFrame.maxX - newSize.width))
        origin.y = max(screenFrame.minY, min(origin.y, screenFrame.maxY - newSize.height))
        return CGRect(origin: origin, size: newSize)
    }

    private static func panelOrigin(
        input: LayoutInput,
        panelSize: CGSize,
        screen: NSScreen
    ) -> CGPoint {
        if input.centerOnScreen {
            let vf = screen.visibleFrame
            return CGPoint(
                x: vf.midX - panelSize.width / 2,
                y: vf.midY - panelSize.height / 2
            )
        }
        guard input.anchorRect != .zero else {
            let mouse = NSEvent.mouseLocation
            return CGPoint(x: mouse.x - panelSize.width / 2, y: mouse.y + 24)
        }
        return DockPreviewPanelGeometry.panelOrigin(
            axIconRect: input.anchorRect,
            panelSize: panelSize,
            screen: screen,
            dockEdge: input.dockEdge,
            bufferFromDock: input.bufferFromDock,
            anchoredIconRect: input.anchoredIconRect,
            isCmdTab: input.isCmdTab
        )
    }
}
