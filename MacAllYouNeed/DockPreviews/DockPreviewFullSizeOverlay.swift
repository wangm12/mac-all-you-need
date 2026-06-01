import AppKit
import SwiftUI

/// Full-size window preview on card hover (DockDoor `FullSizePreviewView` subset).
@MainActor
final class DockPreviewFullSizeOverlay {
    static let shared = DockPreviewFullSizeOverlay()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<FullSizePreviewContent>?

    func show(entry: DockPreviewWindowEntry, liveImage: CGImage?, thumbnail: NSImage?) {
        let content = FullSizePreviewContent(
            title: entry.title,
            liveImage: liveImage,
            thumbnail: thumbnail
        )
        if hostingView == nil {
            let hosting = NSHostingView(rootView: content)
            hostingView = hosting
            let newPanel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newPanel.level = .popUpMenu
            newPanel.backgroundColor = .clear
            newPanel.isFloatingPanel = true
            newPanel.hasShadow = true
            newPanel.contentView = hosting
            panel = newPanel
        } else {
            hostingView?.rootView = content
        }
        guard let panel, let hostingView else { return }
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        let mouse = NSEvent.mouseLocation
        panel.setFrame(
            CGRect(x: mouse.x - size.width / 2, y: mouse.y + 24, width: size.width, height: size.height),
            display: true
        )
        panel.orderFrontRegardless()
    }

    func dismiss() {
        panel?.orderOut(nil)
    }
}

private struct FullSizePreviewContent: View {
    let title: String
    let liveImage: CGImage?
    let thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let liveImage {
                    Image(decorative: liveImage, scale: 1).resizable().aspectRatio(contentMode: .fit)
                } else if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Color.primary.opacity(0.08)
                }
            }
            .frame(maxWidth: 480, maxHeight: 280)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(title).font(.caption).lineLimit(1)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
