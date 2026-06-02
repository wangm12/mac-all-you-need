import AppKit
import SwiftUI

/// Trackpad swipe in preview panel (DockDoor `TrackpadGestureModifier`).
struct DockPreviewTrackpadGestureModifier: ViewModifier {
    let swipeThreshold: CGFloat
    let onSwipeUp: () -> Void
    let onSwipeDown: () -> Void
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void

    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovering = $0 }
            .background(
                DockPreviewTrackpadEventMonitor(
                    isActive: $isHovering,
                    swipeThreshold: swipeThreshold,
                    onSwipeUp: onSwipeUp,
                    onSwipeDown: onSwipeDown,
                    onSwipeLeft: onSwipeLeft,
                    onSwipeRight: onSwipeRight
                )
                .frame(width: 0, height: 0)
            )
    }
}

private struct DockPreviewTrackpadEventMonitor: NSViewRepresentable {
    @Binding var isActive: Bool
    let swipeThreshold: CGFloat
    let onSwipeUp: () -> Void
    let onSwipeDown: () -> Void
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isActive = isActive
        context.coordinator.swipeThreshold = swipeThreshold
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            swipeThreshold: swipeThreshold,
            onSwipeUp: onSwipeUp,
            onSwipeDown: onSwipeDown,
            onSwipeLeft: onSwipeLeft,
            onSwipeRight: onSwipeRight
        )
    }

    final class Coordinator {
        var isActive = false
        var swipeThreshold: CGFloat
        var onSwipeUp: () -> Void
        var onSwipeDown: () -> Void
        var onSwipeLeft: () -> Void
        var onSwipeRight: () -> Void

        private var scrollMonitor: Any?
        private var cumulativeScrollX: CGFloat = 0
        private var cumulativeScrollY: CGFloat = 0
        private var isScrolling = false
        private var isNaturalScrolling = false
        private var scrollEndTimer: Timer?

        init(
            swipeThreshold: CGFloat,
            onSwipeUp: @escaping () -> Void,
            onSwipeDown: @escaping () -> Void,
            onSwipeLeft: @escaping () -> Void,
            onSwipeRight: @escaping () -> Void
        ) {
            self.swipeThreshold = swipeThreshold
            self.onSwipeUp = onSwipeUp
            self.onSwipeDown = onSwipeDown
            self.onSwipeLeft = onSwipeLeft
            self.onSwipeRight = onSwipeRight
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handleScroll(event)
                return event
            }
        }

        deinit {
            if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
            scrollEndTimer?.invalidate()
        }

        private func handleScroll(_ event: NSEvent) {
            guard isActive, event.hasPreciseScrollingDeltas else { return }
            switch event.phase {
            case .began:
                cumulativeScrollX = 0
                cumulativeScrollY = 0
                isScrolling = true
                isNaturalScrolling = event.isDirectionInvertedFromDevice
                scrollEndTimer?.invalidate()
            case .changed:
                cumulativeScrollX += event.scrollingDeltaX
                cumulativeScrollY += event.scrollingDeltaY
            case .ended:
                finishScroll()
            case .cancelled:
                cumulativeScrollX = 0
                cumulativeScrollY = 0
                isScrolling = false
            default:
                break
            }
            scrollEndTimer?.invalidate()
            scrollEndTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
                self?.finishScroll()
            }
        }

        private func finishScroll() {
            guard isScrolling else { return }
            isScrolling = false
            let normalizedY = isNaturalScrolling ? -cumulativeScrollY : cumulativeScrollY
            if abs(cumulativeScrollY) > abs(cumulativeScrollX), abs(cumulativeScrollY) > swipeThreshold {
                if normalizedY > 0 { DispatchQueue.main.async { self.onSwipeUp() } }
                else { DispatchQueue.main.async { self.onSwipeDown() } }
            } else if abs(cumulativeScrollX) > abs(cumulativeScrollY), abs(cumulativeScrollX) > swipeThreshold {
                if cumulativeScrollX < 0 { DispatchQueue.main.async { self.onSwipeLeft() } }
                else { DispatchQueue.main.async { self.onSwipeRight() } }
            }
            cumulativeScrollX = 0
            cumulativeScrollY = 0
        }
    }
}

extension View {
    func dockPreviewTrackpadGestures(
        swipeThreshold: CGFloat,
        onSwipeUp: @escaping () -> Void = {},
        onSwipeDown: @escaping () -> Void = {},
        onSwipeLeft: @escaping () -> Void = {},
        onSwipeRight: @escaping () -> Void = {}
    ) -> some View {
        modifier(DockPreviewTrackpadGestureModifier(
            swipeThreshold: swipeThreshold,
            onSwipeUp: onSwipeUp,
            onSwipeDown: onSwipeDown,
            onSwipeLeft: onSwipeLeft,
            onSwipeRight: onSwipeRight
        ))
    }
}
