import AppKit
import SwiftUI
import UI

enum WindowSnapOverlayPresentation {
    static var cornerRadius: CGFloat {
        if #available(macOS 26.0, *) {
            return 16
        }
        if #available(macOS 11.0, *) {
            return 10
        }
        return 5
    }
    static let respectsReduceMotion = true
    static let usesGlow = false
    static let usesNeutralPalette = true
    static let usesProgressAccent = false
    static let usesFixedBlackOverlay = true
    static let acceptsMouseEvents = false
    static let cancelsStaleDismissAnimation = true
    static let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
    static let visibleAlpha: CGFloat = 0.30
    static let borderWidth: CGFloat = 2
    static let fillColor = NSColor.black
    static let borderColor = NSColor.lightGray
    static let fillOpacity = 1.0
    static let strokeOpacity = 1.0
}

@MainActor
final class WindowSnapOverlayPanel {
    static let shared = WindowSnapOverlayPanel()

    private var panelController: NonActivatingFloatingPanelController<WindowSnapOverlayView>?
    private var dismissGeneration = 0

    func show(frame: CGRect) {
        dismissGeneration += 1

        let size = frame.size

        if panelController == nil {
            let controller = NonActivatingFloatingPanelController<WindowSnapOverlayView>(
                styleMask: WindowSnapOverlayPresentation.styleMask,
                level: FloatingHUDWindowLayering.windowLevel,
                collectionBehavior: FloatingHUDWindowLayering.collectionBehavior,
                hasShadow: WindowSnapOverlayPresentation.usesGlow,
                backgroundColor: .clear,
                showAnimationDuration: MAYNMotionBridge.effectiveDuration(.toastIn),
                hideAnimationDuration: MAYNMotionBridge.effectiveDuration(.toastOut)
            )
            panelController = controller

            // Bootstrap panel creation. We pass animated: false so the controller
            // doesn't install its own fade; we drive show animation below.
            controller.present(rootView: WindowSnapOverlayView(), size: size, animated: false)

            // Configure behaviors the controller doesn't expose directly,
            // then immediately hide so the animate-in path fires on first show.
            if let panel = controller.currentPanel {
                panel.isOpaque = false
                panel.hidesOnDeactivate = false
                panel.ignoresMouseEvents = !WindowSnapOverlayPresentation.acceptsMouseEvents
                panel.alphaValue = 0
                panel.orderOut(nil)
            }
        }

        guard let panel = panelController?.currentPanel else { return }

        panel.setFrame(NSRect(origin: frame.origin, size: size), display: true, animate: false)
        panelController?.update(rootView: WindowSnapOverlayView())

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

    func hide() {
        dismiss()
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

private struct WindowSnapOverlayView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: WindowSnapOverlayPresentation.cornerRadius, style: .continuous)
            .fill(Color(nsColor: WindowSnapOverlayPresentation.fillColor).opacity(WindowSnapOverlayPresentation.fillOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: WindowSnapOverlayPresentation.cornerRadius, style: .continuous)
                    .stroke(
                        Color(nsColor: WindowSnapOverlayPresentation.borderColor).opacity(WindowSnapOverlayPresentation.strokeOpacity),
                        lineWidth: WindowSnapOverlayPresentation.borderWidth
                    )
            )
    }
}
