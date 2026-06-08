import AppKit
import SwiftUI

/// Drag ghost while repositioning a window from preview cards (DockDoor `DragPreviewCoordinator`).
@MainActor
final class DockDragPreviewCoordinator {
    static let shared = DockDragPreviewCoordinator()

    private var previewWindow: NSWindow?
    private var dragStartLocation: CGPoint?
    private var initialFrame: CGRect?
    private let previewScale: CGFloat = 0.2
    private let previewOpacity: CGFloat = 0.5

    func startDragging(entry: DockPreviewWindowEntry, at location: CGPoint) {
        endDragging()
        dragStartLocation = location
        let image = entry.thumbnail.flatMap { thumb in
            thumb.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        guard let image else { return }

        let scaledSize = CGSize(
            width: CGFloat(image.width) * previewScale,
            height: CGFloat(image.height) * previewScale
        )
        let frame = CGRect(
            x: location.x,
            y: location.y - scaledSize.height,
            width: scaledSize.width,
            height: scaledSize.height
        )

        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .popUpMenu
        window.animationBehavior = .none

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: scaledSize))
        imageView.image = NSImage(cgImage: image, size: scaledSize)
        imageView.alphaValue = previewOpacity
        window.contentView = imageView
        window.setFrame(frame, display: true)
        window.orderFront(nil)
        previewWindow = window
        initialFrame = frame
    }

    func updatePosition(to location: CGPoint) {
        guard let start = dragStartLocation, let initial = initialFrame, let window = previewWindow else { return }
        var frame = initial
        frame.origin.x += location.x - start.x
        frame.origin.y += location.y - start.y
        window.setFrame(frame, display: true)
    }

    func endDragging(entry: DockPreviewWindowEntry? = nil) {
        previewWindow?.orderOut(nil)
        previewWindow = nil
        dragStartLocation = nil
        initialFrame = nil
        if let entry {
            Task {
                await DockPreviewRaiseService(enumerator: SystemWindowEnumerator())
                    .raise(entry: entry, settings: DockHubSettingsStore.loadPreviews())
            }
        }
    }
}
