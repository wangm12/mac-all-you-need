import AppKit
import Core
import SwiftUI

/// System-wide floating toast used to confirm an action that originated
/// outside the dock (e.g., copying from the menu bar popover, which itself
/// dismisses immediately and can't host its own feedback view).
///
/// Backed by a borderless `.popUpMenu`-level NSPanel so it appears on top of
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
                contentRect: NSRect(x: 0, y: 0, width: 280, height: 80),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false           // chip's own shadow is enough
            p.level = .popUpMenu
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            p.ignoresMouseEvents = true
            window = p
            return p
        }()

        let hosting = NSHostingView(rootView: HUDChip(message: message, symbol: symbol))
        hosting.frame = NSRect(origin: .zero, size: panel.frame.size)
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
                x: f.midX - panel.frame.width / 2,
                y: f.midY - panel.frame.height / 2
            )
            panel.setFrameOrigin(origin)
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = reduceMotion ? 0 : 0.16
            panel.animator().alphaValue = 1
        }

        hideTask?.cancel()
        hideTask = Task { @MainActor in
            let ms = AppGroupSettings.defaults.integer(forKey: "hudDurationMs")
            let duration = ms > 0 ? ms : 2000
            try? await Task.sleep(for: .milliseconds(duration))
            guard !Task.isCancelled else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = reduceMotion ? 0 : 0.22
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
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.12), in: Circle())
            Text(message)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black, in: Capsule())
        .overlay(
            Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
