import AppKit
import SwiftUI

/// Ghost panel while dragging a preview card (DockDoor `DragPreviewCoordinator` subset).
@MainActor
final class DockPreviewDragCoordinator {
    static let shared = DockPreviewDragCoordinator()

    private var panel: NSPanel?

    func show(image: NSImage, at location: CGPoint) {
        if panel == nil {
            let hosting = NSHostingView(rootView: DragGhost(image: image))
            let newPanel = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newPanel.level = .statusBar
            newPanel.backgroundColor = .clear
            newPanel.isOpaque = false
            newPanel.contentView = hosting
            panel = newPanel
        } else if let hosting = panel?.contentView as? NSHostingView<DragGhost> {
            hosting.rootView = DragGhost(image: image)
        }
        guard let panel else { return }
        let size = CGSize(width: 120, height: 80)
        panel.setFrame(
            CGRect(x: location.x - size.width / 2, y: location.y - size.height / 2, width: size.width, height: size.height),
            display: true
        )
        panel.orderFrontRegardless()
    }

    func endDragging() {
        panel?.orderOut(nil)
    }
}

private struct DragGhost: View {
    let image: NSImage

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .opacity(0.85)
            .shadow(radius: 8)
    }
}
