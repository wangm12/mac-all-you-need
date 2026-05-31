import AppKit
import SwiftUI

@MainActor
final class DockPreviewDismissalTracker: NSView {
    var onMouseEnteredPanel: (() -> Void)?
    var onMouseExitedPanel: (() -> Void)?
    var dockIconRectInWindow: CGRect = .zero
    var onShouldDismiss: (() -> Void)?

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEnteredPanel?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExitedPanel?()
        scheduleDismissCheck()
    }

    func scheduleDismissCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            let mouse = convert(NSEvent.mouseLocation, from: nil)
            if bounds.contains(mouse) { return }
            if dockIconRectInWindow.contains(mouse) { return }
            onShouldDismiss?()
        }
    }
}

struct DockPreviewDismissalContainer<Content: View>: NSViewRepresentable {
    let dockIconRect: CGRect
    let onMouseInPanel: (Bool) -> Void
    let onRequestDismiss: () -> Void
    let content: Content

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        let tracker = DockPreviewDismissalTracker()
        tracker.onMouseEnteredPanel = { onMouseInPanel(true) }
        tracker.onMouseExitedPanel = { onMouseInPanel(false) }
        tracker.dockIconRectInWindow = dockIconRect
        tracker.onShouldDismiss = onRequestDismiss
        tracker.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tracker)
        NSLayoutConstraint.activate([
            tracker.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tracker.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tracker.topAnchor.constraint(equalTo: container.topAnchor),
            tracker.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        context.coordinator.tracker = tracker
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.tracker?.dockIconRectInWindow = dockIconRect
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var tracker: DockPreviewDismissalTracker?
    }
}
