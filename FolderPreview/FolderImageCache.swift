import AppKit
import UniformTypeIdentifiers

// MARK: - Icon Cache

/// Simple dictionary-backed icon cache used by table/outline data sources.
/// Icons are cheap AppKit lookups but repeated per-row; caching avoids
/// redundant NSWorkspace calls on large directories.
final class FolderIconCache {
    private var iconsByKey: [String: NSImage] = [:]

    func reset() {
        iconsByKey.removeAll(keepingCapacity: true)
    }

    func icon(for item: PreviewRow) -> NSImage {
        if item.isDirectory {
            return cached(key: "folder") {
                NSWorkspace.shared.icon(for: .folder)
            }
        }
        let ext = (item.name as NSString).pathExtension.lowercased()
        if let type = UTType(filenameExtension: ext) {
            return cached(key: "type:\(ext)") {
                NSWorkspace.shared.icon(for: type)
            }
        }
        return cached(key: "doc") {
            NSImage(systemSymbolName: "doc", accessibilityDescription: nil) ?? NSImage()
        }
    }

    private func cached(key: String, load: () -> NSImage) -> NSImage {
        if let image = iconsByKey[key] { return image }
        let image = load()
        iconsByKey[key] = image
        return image
    }
}

// MARK: - Thumbnail Generator

import ImageIO
import QuickLookThumbnailing

enum PreviewThumbnailGenerator {
    static func thumbnail(for url: URL, size: CGSize, scale: CGFloat) async throws -> NSImage {
        if let image = try await imageThumbnail(for: url, size: size, scale: scale) {
            return image
        }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )
        return try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    }

    private static func imageThumbnail(for url: URL, size: CGSize, scale: CGFloat) async throws -> NSImage? {
        guard isImage(url) else { return nil }
        return try await Task.detached(priority: .userInitiated) {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }

            let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
                return nil
            }

            let maxPixelSize = max(Int(size.width * scale), Int(size.height * scale))
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
                return nil
            }
            return NSImage(
                cgImage: image,
                size: CGSize(
                    width: CGFloat(image.width) / scale,
                    height: CGFloat(image.height) / scale
                )
            )
        }.value
    }

    private static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }
}
