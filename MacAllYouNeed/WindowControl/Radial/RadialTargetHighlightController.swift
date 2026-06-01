import AppKit
import SwiftUI
import UI

/// Window-sized panel showing a glowing border on the radial target window.
@MainActor
final class RadialTargetHighlightController {
    private var panelController: NonActivatingFloatingPanelController<RadialTargetHighlightView>?
    private var dismissGeneration = 0

    private static var panelLevel: NSWindow.Level {
        NSWindow.Level(rawValue: FloatingHUDWindowLayering.windowLevel.rawValue)
    }

    func show(frame: CGRect, color: Color) {
        dismissGeneration += 1
        let radius = WindowSnapOverlayPresentation.cornerRadius(for: frame.size)
        let highlight = RadialTargetHighlightView(color: color, cornerRadius: radius)

        if panelController == nil {
            let controller = NonActivatingFloatingPanelController<RadialTargetHighlightView>(
                styleMask: WindowSnapOverlayPresentation.styleMask,
                level: Self.panelLevel,
                collectionBehavior: FloatingHUDWindowLayering.collectionBehavior,
                hasShadow: false,
                backgroundColor: .clear,
                showAnimationDuration: MAYNMotionBridge.effectiveDuration(.toastIn),
                hideAnimationDuration: MAYNMotionBridge.effectiveDuration(.toastOut)
            )
            panelController = controller
            controller.present(rootView: highlight, size: frame.size, animated: false)
            if let panel = controller.currentPanel {
                panel.isOpaque = false
                panel.hidesOnDeactivate = false
                panel.ignoresMouseEvents = true
                panel.alphaValue = 0
                panel.orderOut(nil)
            }
        }

        guard let panel = panelController?.currentPanel else { return }
        panel.setFrame(NSRect(origin: frame.origin, size: frame.size), display: true, animate: false)
        panelController?.update(rootView: highlight)

        guard !panel.isVisible else {
            panel.alphaValue = 1
            FloatingHUDWindowLayering.orderFront(panel)
            return
        }

        panel.alphaValue = 0
        FloatingHUDWindowLayering.orderFront(panel)
        animate(panel, to: 1, kind: .toastIn)
    }

    func dismiss() {
        guard let panel = panelController?.currentPanel, panel.isVisible else { return }
        dismissGeneration += 1
        let generation = dismissGeneration
        let duration = MAYNMotionBridge.effectiveDuration(.toastOut)
        guard duration > 0 else {
            panel.orderOut(nil)
            panel.alphaValue = 1
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = MAYNMotionBridge.timingFunction(.toastOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                guard let self, let panel, generation == self.dismissGeneration else { return }
                panel.orderOut(nil)
                panel.alphaValue = 1
            }
        }
    }

    private func animate(_ panel: NSPanel, to alpha: CGFloat, kind: MAYNMotionKind) {
        let duration = MAYNMotionBridge.effectiveDuration(kind)
        guard duration > 0 else {
            panel.alphaValue = alpha
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = MAYNMotionBridge.timingFunction(kind)
            panel.animator().alphaValue = alpha
        }
    }
}
