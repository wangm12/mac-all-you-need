import AppKit
import SwiftUI

/// Floating Quick-Look-style preview panel used by both the dock (⌘⇧V) and
/// the menu bar popover. Borderless `.popUpMenu`-level NSPanel so it
/// appears on top of any active full-screen Space without stealing focus
/// from the underlying app or popover. Dismissed by Space, Esc, or click.
@MainActor
enum PreviewPanel {
    /// Payload kinds the panel knows how to render. Keep this small —
    /// previews that need bespoke chrome (color swatch, file list) should
    /// keep using the in-window QuickLookOverlay.
    enum Content: Equatable {
        case image(NSImage)
        case text(String, monospaced: Bool)
    }

    private static var window: NSPanel?
    private static var keyMonitor: Any?

    static var isVisible: Bool { window?.isVisible ?? false }

    static func show(_ content: Content) {
        let panel: NSPanel = window ?? makePanel()
        window = panel

        let screen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let maxSize = NSSize(width: visible.width * 0.7, height: visible.height * 0.7)

        let fitted = sizeForContent(content, in: maxSize)

        let hosting = NSHostingView(rootView: PreviewBody(content: content))
        hosting.frame = NSRect(origin: .zero, size: fitted)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        let frame = NSRect(
            x: visible.midX - fitted.width / 2,
            y: visible.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
        panel.setFrame(frame, display: true)

        // Don't fade-in if the panel is already visible — re-firing show()
        // for an arrow-nav refresh would cause a perceptible flash that
        // the user noticed at list boundaries. Just swap the contentView
        // and frame.
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                panel.animator().alphaValue = 1
            }
        }

        installKeyMonitor()
    }

    static func dismiss() {
        guard let panel = window, panel.isVisible else { return }
        removeKeyMonitor()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private static func makePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isMovableByWindowBackground = true
        return p
    }

    private static func sizeForContent(_ content: Content, in maxSize: NSSize) -> NSSize {
        switch content {
        case let .image(image):
            let src = image.size
            guard src.width > 0, src.height > 0 else { return maxSize }
            let scale = min(maxSize.width / src.width, maxSize.height / src.height, 1)
            return NSSize(
                width: max(160, src.width * scale),
                height: max(120, src.height * scale)
            )
        case .text:
            // Text previews use a fixed comfortable reading width capped by
            // the screen — same width regardless of content length so
            // navigation across cards doesn't make the panel jump in size.
            let width = min(maxSize.width, 720)
            let height = min(maxSize.height, 520)
            return NSSize(width: width, height: height)
        }
    }

    private static func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { event in
            if event.type == .keyDown {
                let chars = event.charactersIgnoringModifiers ?? ""
                if chars == " " || event.keyCode == 53 /* esc */ {
                    dismiss()
                    return nil
                }
            }
            if event.type == .leftMouseDown { dismiss() }
            return event
        }
    }

    private static func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

private struct PreviewBody: View {
    let content: PreviewPanel.Content

    var body: some View {
        Group {
            switch content {
            case let .image(image):
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            case let .text(string, monospaced):
                ScrollView {
                    Text(string)
                        .font(.system(size: 13, design: monospaced ? .monospaced : .default))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    private var backgroundColor: Color {
        switch content {
        case .image: return Color.black.opacity(0.85)
        case .text: return Color(nsColor: .controlBackgroundColor)
        }
    }
}
