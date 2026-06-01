import AppKit
import SwiftUI

/// Tap, close, and delayed full-size preview (DockDoor `WindowPreviewInteractionModifier` subset).
struct DockPreviewWindowInteractionsModifier: ViewModifier {
    let onSelect: () -> Void
    let onClose: () -> Void
    let enableFullSizeOnHover: Bool
    let entry: DockPreviewWindowEntry
    let liveImage: CGImage?
    let reduceMotion: Bool

    @State private var fullPreviewTimer: Timer?

    func body(content: Content) -> some View {
        content
            .onTapGesture {
                cancelFullPreviewTimer()
                onSelect()
            }
            .onHover { hovering in
                guard enableFullSizeOnHover, !entry.title.isEmpty else { return }
                if hovering {
                    startFullPreviewTimer()
                } else {
                    cancelFullPreviewTimer()
                    DockPreviewFullSizeOverlay.shared.dismiss()
                }
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
        entry: DockPreviewWindowEntry,
        liveImage: CGImage?,
        reduceMotion: Bool
    ) -> some View {
        modifier(DockPreviewWindowInteractionsModifier(
            onSelect: onSelect,
            onClose: onClose,
            enableFullSizeOnHover: enableFullSizeOnHover,
            entry: entry,
            liveImage: liveImage,
            reduceMotion: reduceMotion
        ))
    }
}
