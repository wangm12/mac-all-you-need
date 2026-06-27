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
        panel.collectionBehavior = collectionBehavior
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.ignoresMouseEvents = !acceptsMouseEvents
        // Must follow `isFloatingPanel` — AppKit otherwise snaps the level to `.floating`.
        panel.level = windowLevel
    }

    static func orderFront(_ panel: NSPanel) {
        panel.level = windowLevel
        panel.orderFrontRegardless()
    }
}

/// Clipboard dock sits above generic runtime HUDs so it can paint over the app's
/// own main window on macOS 26 while staying below Voice HUD chrome.
///
/// Document windows (main window, settings sheets) are left untouched — only
/// the dock panel's level/z-order changes so the app stays visible.
@MainActor
enum ClipboardDockWindowLayering {
    static let windowLevel = NSWindow.Level(
        rawValue: FloatingHUDWindowLayering.windowLevel.rawValue + 2
    )
    static let collectionBehavior = FloatingHUDWindowLayering.collectionBehavior

    static func configure(_ panel: NSPanel) {
        FloatingHUDWindowLayering.configure(panel, acceptsMouseEvents: true)
        panel.level = windowLevel
    }

    static func orderFront(_ panel: NSPanel) {
        panel.level = windowLevel
        panel.orderFrontRegardless()
    }

    /// macOS 26 can briefly repromote the main window after in-app triggers
    /// (Open Dock button, toolbar actions). Reassert once the current event
    /// finishes so the dock stays above document chrome.
    static func schedulePresentationRefresh(for panel: NSPanel) {
        DispatchQueue.main.async {
            guard panel.isVisible else { return }
            orderFront(panel)
        }
    }

    static func reassertLevel(_ panel: NSPanel) {
        panel.level = windowLevel
    }

    static func restoreSiblingWindowLevels() {}
}

/// Voice pill, captions, and alerts sit above the clipboard dock and other
/// `.screenSaver` floating HUDs so dictation chrome is never occluded.
enum VoiceHUDWindowLayering {
    static let windowLevel = NSWindow.Level(rawValue: FloatingHUDWindowLayering.windowLevel.rawValue + 4)
    static let collectionBehavior = FloatingHUDWindowLayering.collectionBehavior

    static func configure(_ panel: NSPanel, acceptsMouseEvents: Bool) {
        FloatingHUDWindowLayering.configure(panel, acceptsMouseEvents: acceptsMouseEvents)
        panel.level = windowLevel
    }

    static func orderFront(_ panel: NSPanel) {
        panel.level = windowLevel
        panel.orderFrontRegardless()
    }

    /// Transparent panels so Liquid Glass can sample the desktop behind the HUD.
    static func configureGlassPanel(_ panel: NSPanel, acceptsMouseEvents: Bool) {
        configure(panel, acceptsMouseEvents: acceptsMouseEvents)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
    }
}

/// Tracks bottom-edge UI (clipboard dock) that should lift floating voice HUDs.
@MainActor
enum FloatingBottomObstructionProvider {
    static let didChangeNotification = Notification.Name("FloatingBottomObstructionProvider.didChange")

    /// Extra lift above `visibleFrame.minY` when the clipboard dock is open on this display.
    private(set) static var clipboardDockObstruction: CGFloat = 0
    private(set) static var clipboardDockScreenFrame: NSRect = .zero

    static let clearanceAboveClipboardDock: CGFloat = 12

    static func setClipboardDockVisible(height: CGFloat, on screen: NSScreen) {
        let obstruction = max(0, height) + clearanceAboveClipboardDock
        applyClipboardDockObstruction(obstruction, screenFrame: screen.frame)
    }

    static func clearClipboardDockObstruction() {
        applyClipboardDockObstruction(0, screenFrame: .zero)
    }

    static func bottomObstruction(for visibleFrame: NSRect) -> CGFloat {
        guard clipboardDockObstruction > 0, !clipboardDockScreenFrame.isEmpty else { return 0 }
        guard framesShareDisplay(visibleFrame, clipboardDockScreenFrame) else { return 0 }
        return clipboardDockObstruction
    }

    private static func applyClipboardDockObstruction(_ height: CGFloat, screenFrame: NSRect) {
        guard clipboardDockObstruction != height || clipboardDockScreenFrame != screenFrame else { return }
        clipboardDockObstruction = height
        clipboardDockScreenFrame = screenFrame
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    private static func framesShareDisplay(_ visibleFrame: NSRect, _ screenFrame: NSRect) -> Bool {
        visibleFrame.intersects(screenFrame)
            || NSContainsRect(screenFrame, visibleFrame)
            || NSContainsRect(visibleFrame, screenFrame)
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
                .foregroundStyle(MAYNTheme.hudForeground)
                .frame(
                    width: CGFloat(MAYNNotificationPillPresentation.iconFrameSize),
                    height: CGFloat(MAYNNotificationPillPresentation.iconFrameSize)
                )
            Text(message)
                .font(.system(size: CGFloat(MAYNNotificationPillPresentation.titleFontSize), weight: .semibold))
                .foregroundStyle(MAYNTheme.hudForeground)
        }
        .padding(.horizontal, CGFloat(MAYNNotificationPillPresentation.horizontalPadding))
        .padding(.vertical, CGFloat(MAYNNotificationPillPresentation.verticalPadding))
        .background(MAYNTheme.hudBackground, in: Capsule())
        .overlay {
            if MAYNNotificationPillPresentation.hasCapsuleStroke {
                Capsule().stroke(MAYNTheme.hairline, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
        .accessibilityValue("Copied")
        .frame(width: MAYNNotificationPillPresentation.copyPanelSize(message: message).width,
               height: MAYNNotificationPillPresentation.copyPanelHeight)
    }
}
