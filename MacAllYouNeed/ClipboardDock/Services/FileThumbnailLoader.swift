import AppKit
import Foundation
import QuickLookThumbnailing

/// Generates a thumbnail for an arbitrary file URL via QuickLookThumbnailing.
/// Used by FileCard so a clipboard entry like a CleanShot screenshot file URL
/// renders the actual image preview instead of just the generic file icon —
/// matching Paste.app's behavior. Works for images, PDFs, video posters,
/// office documents, and anything else QL knows how to render.
actor FileThumbnailLoader {
    private let cache = NSCache<NSString, NSImage>()

    init(totalCostLimitBytes: Int = 32 * 1024 * 1024) {
        cache.totalCostLimit = totalCostLimitBytes
    }

    func thumbnail(url: URL, maxDim: Int) async -> NSImage? {
        let key = "\(url.path)|\(maxDim)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        // .all asks QL to pick the best of icon / low-quality / high-quality
        // representations available for this file type.
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: CGFloat(maxDim), height: CGFloat(maxDim)),
            scale: NSScreen.main?.backingScaleFactor ?? 2.0,
            representationTypes: .all
        )
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        let image = rep.nsImage
        // Rough cost: width * height * 4 bytes/pixel.
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }
}
