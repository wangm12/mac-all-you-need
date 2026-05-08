import AppKit
import Core
import Foundation
import Platform

actor ImageBlobLoader {
    private let xpc: any ClipboardXPCInteracting
    /// Optional in-process read path. When both stores are present, thumbnails
    /// are decoded from the encrypted BlobStore directly — same path the
    /// daemon uses internally — bypassing XPC. This is required because the
    /// daemon's mach service registration silently fails on macOS Sequoia
    /// debug builds, so xpc.imageThumbnail returns nil and cards otherwise
    /// show empty placeholders.
    private let clip: ClipboardStore?
    private let blobs: BlobStore?
    private let cache = NSCache<NSString, NSImage>()

    init(
        xpc: any ClipboardXPCInteracting,
        clip: ClipboardStore? = nil,
        blobs: BlobStore? = nil,
        totalCostLimitBytes: Int = 64 * 1024 * 1024
    ) {
        self.xpc = xpc
        self.clip = clip
        self.blobs = blobs
        cache.totalCostLimit = totalCostLimitBytes
    }

    func thumbnail(recordID: String, maxDim: Int) async -> NSImage? {
        let key = "\(recordID)|\(maxDim)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        if let local = await loadLocal(recordID: recordID, maxDim: maxDim) {
            cache.setObject(local.image, forKey: key, cost: local.dataCount)
            return local.image
        }

        guard let data = await xpc.imageThumbnail(forID: recordID, maxDim: maxDim),
              let image = NSImage(data: data) else {
            return nil
        }
        cache.setObject(image, forKey: key, cost: data.count)
        return image
    }

    /// Reads the encrypted blob from disk and renders a thumbnail off-actor.
    /// Returns nil when stores aren't injected (test mocks) or the record is
    /// not an image kind / blob is unreadable.
    private func loadLocal(recordID: String, maxDim: Int) async -> (image: NSImage, dataCount: Int)? {
        guard let clip, let blobs, let rid = RecordID(rawValue: recordID) else { return nil }
        return await Task.detached {
            guard let body = try? clip.body(for: rid),
                  case let .image(blobID, _, _) = body,
                  let raw = try? blobs.read(id: blobID),
                  let rendered = ThumbnailRenderer.render(data: raw, maxDim: maxDim),
                  let image = NSImage(data: rendered)
            else { return nil }
            return (image, rendered.count)
        }.value
    }
}
