import AppKit
import Foundation

/// Protocol seam for thumbnail capture.
protocol ThumbnailCapturing: Sendable {
    func capture(
        windowID: CGWindowID,
        scale: CGFloat,
        quality: DockWindowImageCaptureQuality
    ) async -> NSImage?
}

/// Live thumbnail service using the CGS private API via `DockPreviewPrivateAPI`.
final class DockPreviewThumbnailService: ThumbnailCapturing, @unchecked Sendable {
    private let api: any DockPreviewPrivateAPI
    private let scheduler: DockPreviewCaptureScheduler

    init(
        api: any DockPreviewPrivateAPI = SystemDockPreviewPrivateAPI(),
        scheduler: DockPreviewCaptureScheduler = DockPreviewCaptureScheduler()
    ) {
        self.api = api; self.scheduler = scheduler
    }

    func capture(
        windowID: CGWindowID,
        scale: CGFloat,
        quality: DockWindowImageCaptureQuality
    ) async -> NSImage? {
        await scheduler.acquire()
        defer { Task { await scheduler.release() } }
        guard let cgImage = api.captureWindowThumbnail(windowID: windowID, scale: scale, quality: quality)
        else { return nil }
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        return NSImage(cgImage: cgImage, size: size)
    }
}
