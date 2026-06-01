import AppKit
import SwiftUI

/// Trackpad swipe in preview panel (DockDoor `TrackpadGestureModifier` subset).
struct DockPreviewTrackpadSwipeModifier: ViewModifier {
    let onSwipe: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content.background(DockPreviewTrackpadSwipeMonitor(onSwipe: onSwipe))
    }
}

private struct DockPreviewTrackpadSwipeMonitor: NSViewRepresentable {
    let onSwipe: (CGFloat) -> Void

    func makeNSView(context: Context) -> DockPreviewSwipeNSView {
        let view = DockPreviewSwipeNSView()
        view.onSwipe = onSwipe
        return view
    }

    func updateNSView(_ nsView: DockPreviewSwipeNSView, context: Context) {
        nsView.onSwipe = onSwipe
    }
}

final class DockPreviewSwipeNSView: NSView {
    var onSwipe: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY), abs(event.scrollingDeltaX) > 2 {
            onSwipe?(event.scrollingDeltaX)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

extension View {
    func dockPreviewTrackpadSwipe(onSwipe: @escaping (CGFloat) -> Void) -> some View {
        modifier(DockPreviewTrackpadSwipeModifier(onSwipe: onSwipe))
    }
}
