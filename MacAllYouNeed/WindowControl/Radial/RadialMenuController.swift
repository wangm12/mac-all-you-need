import AppKit
import Core
import SwiftUI
import UI

/// Borderless NSPanel hosting the radial menu.
@MainActor
final class RadialMenuController {
    private var panelController: NonActivatingFloatingPanelController<RadialMenuHost>?
    private var dismissGeneration = 0
    private let viewModel: RadialMenuViewModel

    private static var panelLevel: NSWindow.Level {
        NSWindow.Level(rawValue: FloatingHUDWindowLayering.windowLevel.rawValue + 1)
    }

    init(viewModel: RadialMenuViewModel) {
        self.viewModel = viewModel
    }

    /// `point` is the menu center in AppKit (bottom-left origin) coordinates.
    func show(at point: NSPoint) {
        dismissGeneration += 1
        let size = RadialPuckMetrics.panelSize
        let originPoint = RadialPuckMetrics.panelOriginAppKit(menuCenter: CGPoint(x: point.x, y: point.y))
        let origin = NSPoint(x: originPoint.x, y: originPoint.y)
        let frame = NSRect(origin: origin, size: size)

        if panelController == nil {
            let controller = NonActivatingFloatingPanelController<RadialMenuHost>(
                styleMask: WindowSnapOverlayPresentation.styleMask,
                level: Self.panelLevel,
                collectionBehavior: FloatingHUDWindowLayering.collectionBehavior,
                hasShadow: false,
                backgroundColor: .clear,
                showAnimationDuration: MAYNMotionBridge.effectiveDuration(.toastIn),
                hideAnimationDuration: MAYNMotionBridge.effectiveDuration(.toastOut)
            )
            panelController = controller
            controller.present(rootView: RadialMenuHost(viewModel: viewModel), size: size, animated: false)
            if let panel = controller.currentPanel {
                panel.isOpaque = false
                panel.hidesOnDeactivate = false
                panel.ignoresMouseEvents = true
                panel.alphaValue = 0
                panel.setFrame(frame, display: true)
                panel.orderOut(nil)
            }
        }

        guard let panel = panelController?.currentPanel else { return }
        panel.setFrame(frame, display: true)
        panelController?.update(rootView: RadialMenuHost(viewModel: viewModel))

        guard !panel.isVisible else {
            panel.alphaValue = 1
            panel.level = Self.panelLevel
            panel.orderFrontRegardless()
            return
        }

        panel.alphaValue = 0
        panel.level = Self.panelLevel
        panel.orderFrontRegardless()
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

private struct RadialMenuHost: View {
    @ObservedObject var viewModel: RadialMenuViewModel

    var body: some View {
        RadialMenuView(viewModel: viewModel)
    }
}
