import AppKit
import SwiftUI

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

    private var panel: NSPanel?
    private var hostingView: NSHostingView<WindowSnapOverlayView>?
    private var dismissGeneration = 0

    func show(frame: CGRect) {
        dismissGeneration += 1
        let frame = NSRect(origin: frame.origin, size: frame.size)
        let panel = panel ?? makePanel(frame: frame)
        self.panel = panel

        FloatingHUDWindowLayering.configure(panel, acceptsMouseEvents: WindowSnapOverlayPresentation.acceptsMouseEvents)
        panel.hasShadow = WindowSnapOverlayPresentation.usesGlow
        panel.setFrame(frame, display: true, animate: false)

        let overlay = WindowSnapOverlayView()
        if let hostingView {
            hostingView.rootView = overlay
            hostingView.frame = NSRect(origin: .zero, size: frame.size)
        } else {
            let hostingView = NSHostingView(rootView: overlay)
            hostingView.frame = NSRect(origin: .zero, size: frame.size)
            hostingView.autoresizingMask = [.width, .height]
            panel.contentView = hostingView
            self.hostingView = hostingView
        }

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
        guard let panel, panel.isVisible else { return }
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

    private func makePanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: WindowSnapOverlayPresentation.styleMask,
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = WindowSnapOverlayPresentation.usesGlow
        FloatingHUDWindowLayering.configure(panel, acceptsMouseEvents: WindowSnapOverlayPresentation.acceptsMouseEvents)
        return panel
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
