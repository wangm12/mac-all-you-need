import AppKit
import SwiftUI
import UI

enum WindowSnapOverlayPresentation {
    /// Overall panel opacity while visible (Rectangle-style footprint alpha).
    static let visibleAlpha: CGFloat = 0.52
    static let borderWidth: CGFloat = 2
    static let fillColor = NSColor.black
    static let borderColor = NSColor(white: 0.65, alpha: 1)
    static let fillOpacity = 1.0
    static let strokeOpacity = 1.0

    static let respectsReduceMotion = true
    static let usesGlow = false
    static let usesNeutralPalette = true
    static let usesProgressAccent = false
    static let usesFixedBlackOverlay = true
    static let acceptsMouseEvents = false
    static let cancelsStaleDismissAnimation = true
    static let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]

    /// Cached radius read from a transient titled window, else OS defaults (10 / 16 / 5).
    @MainActor
    static var standardCornerRadius: CGFloat {
        if let cached = _cachedStandardCornerRadius {
            return cached
        }
        let measured = measureSystemWindowCornerRadius()
        _cachedStandardCornerRadius = measured
        return measured
    }

    @MainActor
    private static var _cachedStandardCornerRadius: CGFloat?

    /// Corner radius for a proposed frame, clamped to the overlay size.
    @MainActor
    static func cornerRadius(for size: CGSize) -> CGFloat {
        let system = standardCornerRadius
        guard size.width > 1, size.height > 1 else { return system }
        return min(system, min(size.width, size.height) / 2)
    }

    /// Legacy alias used by tests and call sites that do not have a frame size yet.
    @MainActor
    static var cornerRadius: CGFloat { standardCornerRadius }

    @MainActor
    private static func measureSystemWindowCornerRadius() -> CGFloat {
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 320, height: 240),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.layoutIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()

        if let radius = largestLayerCornerRadius(in: window.contentView), radius >= 4 {
            return radius
        }
        return fallbackCornerRadiusForOS()
    }

    private static func fallbackCornerRadiusForOS() -> CGFloat {
        if #available(macOS 26.0, *) {
            return 16
        }
        if #available(macOS 11.0, *) {
            return 10
        }
        return 5
    }

    private static func largestLayerCornerRadius(in view: NSView?) -> CGFloat? {
        guard let view else { return nil }
        var best: CGFloat = 0
        func walk(_ node: NSView) {
            if let layer = node.layer {
                best = max(best, layer.cornerRadius)
            }
            for subview in node.subviews {
                walk(subview)
            }
        }
        walk(view)
        return best > 0.5 ? best : nil
    }
}

@MainActor
final class WindowSnapOverlayPanel {
    static let shared = WindowSnapOverlayPanel()

    private var panelController: NonActivatingFloatingPanelController<WindowLayoutPreviewRectView>?
    private var dismissGeneration = 0

    func show(frame: CGRect) {
        dismissGeneration += 1

        let size = frame.size
        let radius = WindowSnapOverlayPresentation.cornerRadius(for: size)
        let preview = WindowLayoutPreviewRectView(cornerRadius: radius)

        if panelController == nil {
            let controller = NonActivatingFloatingPanelController<WindowLayoutPreviewRectView>(
                styleMask: WindowSnapOverlayPresentation.styleMask,
                level: FloatingHUDWindowLayering.windowLevel,
                collectionBehavior: FloatingHUDWindowLayering.collectionBehavior,
                hasShadow: WindowSnapOverlayPresentation.usesGlow,
                backgroundColor: .clear,
                showAnimationDuration: MAYNMotionBridge.effectiveDuration(.toastIn),
                hideAnimationDuration: MAYNMotionBridge.effectiveDuration(.toastOut)
            )
            panelController = controller

            controller.present(rootView: preview, size: size, animated: false)

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
        panelController?.update(rootView: preview)

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

/// Shared destination-preview rect for edge snap and radial menu (design.md §10.6).
/// Uses `NSBox` so corner curvature matches Rectangle / native window footprints.
struct WindowLayoutPreviewRectView: NSViewRepresentable {
    var cornerRadius: CGFloat = WindowSnapOverlayPresentation.standardCornerRadius

    func makeNSView(context: Context) -> NSBox {
        let box = NSBox()
        applyStyle(to: box)
        return box
    }

    func updateNSView(_ box: NSBox, context: Context) {
        applyStyle(to: box)
    }

    private func applyStyle(to box: NSBox) {
        box.boxType = .custom
        box.borderColor = WindowSnapOverlayPresentation.borderColor
        box.borderWidth = WindowSnapOverlayPresentation.borderWidth
        box.cornerRadius = cornerRadius
        box.fillColor = WindowSnapOverlayPresentation.fillColor
        box.wantsLayer = true
    }
}
