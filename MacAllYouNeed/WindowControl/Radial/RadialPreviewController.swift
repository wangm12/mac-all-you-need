import AppKit
import SwiftUI
import UI

/// Screen-sized, click-through NSPanel that renders the proposed-frame preview.
@MainActor
final class RadialPreviewController {
    private var panelController: NonActivatingFloatingPanelController<RadialPreviewHost>?
    private var dismissGeneration = 0
    private let viewModel: RadialPreviewViewModel
    private var screenFrame: CGRect = .zero

    private static var panelLevel: NSWindow.Level {
        NSWindow.Level(rawValue: FloatingHUDWindowLayering.windowLevel.rawValue)
    }

    init(viewModel: RadialPreviewViewModel) {
        self.viewModel = viewModel
    }

    func show(on screen: NSScreen) {
        dismissGeneration += 1
        screenFrame = screen.frame

        if panelController == nil {
            let controller = NonActivatingFloatingPanelController<RadialPreviewHost>(
                styleMask: WindowSnapOverlayPresentation.styleMask,
                level: Self.panelLevel,
                collectionBehavior: FloatingHUDWindowLayering.collectionBehavior,
                hasShadow: false,
                backgroundColor: .clear,
                showAnimationDuration: MAYNMotionBridge.effectiveDuration(.toastIn),
                hideAnimationDuration: MAYNMotionBridge.effectiveDuration(.toastOut)
            )
            panelController = controller
            controller.present(
                rootView: RadialPreviewHost(viewModel: viewModel, screenFrame: screen.frame),
                size: screen.frame.size,
                animated: false
            )
            if let panel = controller.currentPanel {
                panel.isOpaque = false
                panel.hidesOnDeactivate = false
                panel.ignoresMouseEvents = true
                panel.alphaValue = 0
                panel.setFrame(screen.frame, display: true)
                panel.orderOut(nil)
            }
        }

        guard let panel = panelController?.currentPanel else { return }
        panel.setFrame(screen.frame, display: true)
        panelController?.update(rootView: RadialPreviewHost(viewModel: viewModel, screenFrame: screen.frame))

        guard !panel.isVisible else {
            panel.alphaValue = WindowSnapOverlayPresentation.visibleAlpha
            FloatingHUDWindowLayering.orderFront(panel)
            return
        }

        panel.alphaValue = 0
        FloatingHUDWindowLayering.orderFront(panel)
        animate(panel, to: WindowSnapOverlayPresentation.visibleAlpha, kind: .toastIn)
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

private struct RadialPreviewHost: View {
    @ObservedObject var viewModel: RadialPreviewViewModel
    let screenFrame: CGRect

    var body: some View {
        Group {
            if let frame = viewModel.proposedFrame {
                RadialPreviewView(
                    frame: frame,
                    screenFrame: screenFrame,
                    fullScreenBlend: viewModel.fullScreenBlend,
                    previewOpacity: viewModel.previewOpacity,
                    cornerRadius: viewModel.previewCornerRadius
                )
            } else {
                Color.clear
            }
        }
    }
}
