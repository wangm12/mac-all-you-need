import AppKit
import SwiftUI

/// Floating chip that appears when a video URL is copied to the clipboard.
/// Offers a one-click "Download" action for ~4 seconds, then auto-dismisses.
/// Same `.popUpMenu`-level NSPanel as CopyHUD, but interactive (not mouse-ignoring).
@MainActor
enum AutoDownloadHUD {
    private static var window: NSPanel?
    private static var hideTask: Task<Void, Never>?
    // Per-URL throttle — won't prompt for the same URL within 30 seconds.
    private static var shown: [URL: Date] = [:]

    static func prompt(for url: URL) {
        // Throttle check
        if let last = shown[url], Date().timeIntervalSince(last) < 30 { return }
        shown[url] = Date()

        let panel: NSPanel = {
            if let existing = window { return existing }
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 72),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.level = .popUpMenu
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            p.ignoresMouseEvents = false
            window = p
            return p
        }()

        let hosting = NSHostingView(rootView: AutoDownloadChip(url: url) {
            dismiss()
        })
        hosting.frame = NSRect(origin: .zero, size: panel.frame.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
        if let screen {
            let f = screen.visibleFrame
            // Position slightly below center so it doesn't overlap the menu bar
            let origin = NSPoint(
                x: f.midX - panel.frame.width / 2,
                y: f.midY - panel.frame.height / 2 - 60
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

        scheduleAutoDismiss()
    }

    static func dismiss() {
        hideTask?.cancel()
        guard let panel = window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private static func scheduleAutoDismiss() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }
}

private struct AutoDownloadChip: View {
    let url: URL
    let onDismiss: () -> Void
    @State private var isHoveringDownload = false

    private var displayHost: String {
        url.host?.lowercased()
            .replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.to.line.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text("Video link copied")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Text(displayHost)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .lineLimit(1)
            }

            Spacer()

            Button {
                NotificationCenter.default.post(name: .clipboardDownloadRequested, object: url)
                AutoDownloadHUD.dismiss()
            } label: {
                Text("Download")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white, in: Capsule())
            }
            .buttonStyle(.borderless)

            Button {
                AutoDownloadHUD.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
