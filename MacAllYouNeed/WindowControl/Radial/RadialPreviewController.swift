import AppKit
import SwiftUI

/// Screen-sized, click-through NSPanel that renders the proposed-frame preview.
@MainActor
final class RadialPreviewController {
    private var panel: NSPanel?
    private let viewModel: RadialPreviewViewModel

    init(viewModel: RadialPreviewViewModel) {
        self.viewModel = viewModel
    }

    func show(on screen: NSScreen) {
        if panel == nil {
            panel = makePanel(frame: screen.frame)
        }
        guard let panel else { return }
        panel.setFrame(screen.frame, display: true)
        panel.contentView = NSHostingView(
            rootView: RadialPreviewHost(viewModel: viewModel, screenFrame: screen.frame)
        )
        panel.orderFrontRegardless()
    }

    func dismiss() {
        panel?.orderOut(nil)
    }

    private func makePanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }
}

private struct RadialPreviewHost: View {
    @ObservedObject var viewModel: RadialPreviewViewModel
    let screenFrame: CGRect

    var body: some View {
        Group {
            if let frame = viewModel.proposedFrame {
                RadialPreviewView(frame: frame, screenFrame: screenFrame)
            } else {
                Color.clear
            }
        }
    }
}
