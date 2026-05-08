import AppKit
import QuartzCore

enum DockAnimator {
    static let showDuration: TimeInterval = 0.22
    static let hideDuration: TimeInterval = 0.18

    static func slideUp(_ window: NSWindow, finalOrigin: NSPoint, completion: @escaping () -> Void) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            window.setFrameOrigin(finalOrigin)
            window.alphaValue = 1
            completion()
            return
        }

        var startFrame = window.frame
        startFrame.origin.y = finalOrigin.y - startFrame.height
        window.setFrame(startFrame, display: false)
        window.alphaValue = 0

        NSAnimationContext.runAnimationGroup { context in
            context.duration = showDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            window.animator().setFrameOrigin(finalOrigin)
            window.animator().alphaValue = 1
        } completionHandler: {
            completion()
        }
    }

    static func slideDown(_ window: NSWindow, completion: @escaping () -> Void) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            window.alphaValue = 0
            completion()
            return
        }

        var endFrame = window.frame
        endFrame.origin.y -= endFrame.height
        NSAnimationContext.runAnimationGroup { context in
            context.duration = hideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(endFrame, display: true)
            window.animator().alphaValue = 0
        } completionHandler: {
            completion()
        }
    }
}
