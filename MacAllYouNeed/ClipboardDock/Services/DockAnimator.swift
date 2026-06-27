import AppKit
import QuartzCore

enum DockAnimator {
    static let showDuration: TimeInterval = MAYNMotionDuration.panel
    static let hideDuration: TimeInterval = MAYNMotionDuration.toastIn

    /// Slide a borderless NSPanel up to `finalOrigin` from below the screen.
    ///
    /// Implementation note: NSWindow.setFrame(animate: true) blocks the main
    /// thread for the full duration (~200ms) — that made every ⌘⇧V feel
    /// janky. window.animator().setFrameOrigin doesn't move borderless
    /// nonactivating panels at all. The reliable non-blocking path is to
    /// snap the window to its final position and animate the CONTENT VIEW's
    /// layer (translation + opacity) via Core Animation.
    static func slideUp(_ window: NSWindow, finalOrigin: NSPoint, completion: @escaping () -> Void) {
        let finalFrame = NSRect(origin: finalOrigin, size: window.frame.size)
        window.setFrame(finalFrame, display: true)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            window.alphaValue = 1
            completion()
            return
        }

        guard let layer = window.contentView?.layer ?? makeLayerBackedContentView(window: window) else {
            window.alphaValue = 1
            completion()
            return
        }
        window.alphaValue = 1

        let translate = CABasicAnimation(keyPath: "transform.translation.y")
        translate.fromValue = 16
        translate.toValue = 0
        translate.duration = MAYNMotionBridge.effectiveDuration(.control, reduceMotion: reduceMotion)
        translate.timingFunction = MAYNMotionBridge.timingFunction(.control)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.96
        scale.toValue = 1
        scale.duration = MAYNMotionBridge.effectiveDuration(.control, reduceMotion: reduceMotion)
        scale.timingFunction = MAYNMotionBridge.timingFunction(.control)

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = MAYNMotionBridge.effectiveDuration(.control, reduceMotion: reduceMotion)
        fade.timingFunction = MAYNMotionBridge.timingFunction(.control)

        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        layer.add(translate, forKey: "slide-up-y")
        layer.add(scale, forKey: "slide-up-scale")
        layer.add(fade, forKey: "slide-up-opacity")
        CATransaction.commit()
    }

    static func slideDown(_ window: NSWindow, completion: @escaping () -> Void) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            window.alphaValue = 0
            completion()
            return
        }

        guard let layer = window.contentView?.layer else {
            window.alphaValue = 0
            completion()
            return
        }

        let translate = CABasicAnimation(keyPath: "transform.translation.y")
        translate.fromValue = 0
        translate.toValue = 10
        translate.duration = MAYNMotionBridge.effectiveDuration(.toastIn, reduceMotion: reduceMotion)
        translate.timingFunction = MAYNMotionBridge.timingFunction(.toastIn)
        translate.fillMode = .forwards
        translate.isRemovedOnCompletion = false

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = MAYNMotionBridge.effectiveDuration(.toastIn, reduceMotion: reduceMotion)
        fade.timingFunction = MAYNMotionBridge.timingFunction(.toastOut)
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        layer.add(translate, forKey: "slide-down-y")
        layer.add(fade, forKey: "slide-down-opacity")
        CATransaction.commit()
    }

    private static func makeLayerBackedContentView(window: NSWindow) -> CALayer? {
        window.contentView?.wantsLayer = true
        return window.contentView?.layer
    }
}
