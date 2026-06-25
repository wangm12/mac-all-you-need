import AppKit
import Core
import SwiftUI

enum FloatingHUDWindowLayering {
    static let windowLevel = NSWindow.Level.screenSaver
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .stationary,
        .ignoresCycle
    ]

    static func configure(_ panel: NSPanel, acceptsMouseEvents: Bool) {
        panel.level = windowLevel
        panel.collectionBehavior = collectionBehavior
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.ignoresMouseEvents = !acceptsMouseEvents
    }

    static func orderFront(_ panel: NSPanel) {
        panel.level = windowLevel
        panel.orderFrontRegardless()
    }
}

/// System-wide floating toast used to confirm an action that originated
/// outside the dock (e.g., copying from the menu bar popover, which itself
/// dismisses immediately and can't host its own feedback view).
///
/// Backed by a top-level borderless NSPanel so it appears on top of
/// any active full-screen Space without stealing focus from the user's
/// previous app — they should still be able to ⌘V right after copying.
@MainActor
enum CopyHUD {
    private static var window: NSPanel?
    private static var hideTask: Task<Void, Never>?

    static func show(_ message: String, symbol: String = "checkmark.circle.fill") {
        let panel: NSPanel = {
            if let existing = window { return existing }
            let p = NSPanel(
                contentRect: NSRect(origin: .zero, size: MAYNNotificationPillPresentation.copyPanelSize(message: message)),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = MAYNNotificationPillPresentation.hasOuterShadow
            FloatingHUDWindowLayering.configure(p, acceptsMouseEvents: false)
            window = p
            return p
        }()
        FloatingHUDWindowLayering.configure(panel, acceptsMouseEvents: false)

        let panelSize = MAYNNotificationPillPresentation.copyPanelSize(message: message)
        panel.setContentSize(panelSize)
        panel.hasShadow = MAYNNotificationPillPresentation.hasOuterShadow

        let hosting = NSHostingView(rootView: HUDChip(message: message, symbol: symbol))
        hosting.frame = NSRect(origin: .zero, size: panelSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        // Center on the screen the cursor is currently on so the toast
        // shows up near where the user is looking, not on a stale primary.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
        if let screen {
            let f = screen.visibleFrame
            let origin = NSPoint(
                x: f.midX - panelSize.width / 2,
                y: f.midY - panelSize.height / 2
            )
            panel.setFrameOrigin(origin)
        }

        panel.alphaValue = 0
        FloatingHUDWindowLayering.orderFront(panel)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = MAYNMotionBridge.effectiveDuration(.toastIn)
            panel.animator().alphaValue = 1
        }

        hideTask?.cancel()
        hideTask = Task { @MainActor in
            let ms = AppGroupSettings.defaults.integer(forKey: "hudDurationMs")
            let duration = ms > 0 ? ms : 2000
            try? await Task.sleep(for: .milliseconds(duration))
            guard !Task.isCancelled else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = MAYNMotionBridge.effectiveDuration(.toastOut)
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
            })
        }
    }
}

private struct HUDChip: View {
    let message: String
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: CGFloat(MAYNNotificationPillPresentation.iconSize), weight: .bold))
                .foregroundStyle(.white)
                .frame(
                    width: CGFloat(MAYNNotificationPillPresentation.iconFrameSize),
                    height: CGFloat(MAYNNotificationPillPresentation.iconFrameSize)
                )
            Text(message)
                .font(.system(size: CGFloat(MAYNNotificationPillPresentation.titleFontSize), weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, CGFloat(MAYNNotificationPillPresentation.horizontalPadding))
        .padding(.vertical, CGFloat(MAYNNotificationPillPresentation.verticalPadding))
        .background(Color.black, in: Capsule())
        .overlay {
            if MAYNNotificationPillPresentation.hasCapsuleStroke {
                Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
        .accessibilityValue("Copied")
        .frame(width: MAYNNotificationPillPresentation.copyPanelSize(message: message).width,
               height: MAYNNotificationPillPresentation.copyPanelHeight)
    }
}
