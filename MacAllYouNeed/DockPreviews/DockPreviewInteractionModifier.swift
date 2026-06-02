import AppKit
import SwiftUI

/// Tap, close, drag ghost, and delayed full-size preview (DockDoor `WindowPreviewInteractionModifier` subset).
struct DockPreviewWindowInteractionsModifier: ViewModifier {
    let onSelect: () -> Void
    let onClose: () -> Void
    let enableFullSizeOnHover: Bool
    let enableWindowDrag: Bool
    let entry: DockPreviewWindowEntry
    let liveImage: CGImage?
    let reduceMotion: Bool

    @State private var fullPreviewTimer: Timer?
    @State private var isDragging = false

    func body(content: Content) -> some View {
        content
            .gesture(windowDragGesture)
            .onTapGesture {
                cancelFullPreviewTimer()
                guard !isDragging else { return }
                onSelect()
            }
            .onHover { hovering in
                guard enableFullSizeOnHover, !entry.title.isEmpty, !isDragging else { return }
                if hovering {
                    startFullPreviewTimer()
                } else {
                    cancelFullPreviewTimer()
                    DockPreviewFullSizeOverlay.shared.dismiss()
                }
            }
    }

    private var windowDragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard enableWindowDrag, !entry.title.isEmpty else { return }
                if !isDragging {
                    isDragging = true
                    DockDragPreviewCoordinator.shared.startDragging(
                        entry: entry,
                        at: NSEvent.mouseLocation
                    )
                }
                DockDragPreviewCoordinator.shared.updatePosition(to: NSEvent.mouseLocation)
            }
            .onEnded { _ in
                guard isDragging else { return }
                isDragging = false
                DockDragPreviewCoordinator.shared.endDragging()
            }
    }

    private func startFullPreviewTimer() {
        cancelFullPreviewTimer()
        fullPreviewTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { _ in
            Task { @MainActor in
                DockPreviewFullSizeOverlay.shared.show(
                    entry: entry,
                    liveImage: liveImage,
                    thumbnail: entry.thumbnail
                )
            }
        }
    }

    private func cancelFullPreviewTimer() {
        fullPreviewTimer?.invalidate()
        fullPreviewTimer = nil
    }
}

extension View {
    func dockPreviewWindowInteractions(
        onSelect: @escaping () -> Void,
        onClose: @escaping () -> Void,
        enableFullSizeOnHover: Bool,
        enableWindowDrag: Bool = false,
        entry: DockPreviewWindowEntry,
        liveImage: CGImage?,
        reduceMotion: Bool
    ) -> some View {
        modifier(DockPreviewWindowInteractionsModifier(
            onSelect: onSelect,
            onClose: onClose,
            enableFullSizeOnHover: enableFullSizeOnHover,
            enableWindowDrag: enableWindowDrag,
            entry: entry,
            liveImage: liveImage,
            reduceMotion: reduceMotion
        ))
    }
}
