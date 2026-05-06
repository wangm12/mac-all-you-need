import AppKit
import Foundation
import QuickLookThumbnailing

public final class ThumbnailService {
    private let cacheRoot: URL
    public init(cacheRoot: URL) {
        self.cacheRoot = cacheRoot
        try? FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    }

    public func thumbnail(for url: URL, size: CGSize) async throws -> NSImage? {
        let key = try cacheKey(for: url, size: size)
        let cached = cacheRoot.appendingPathComponent("\(key).png")
        if let data = try? Data(contentsOf: cached), let img = NSImage(data: data) { return img }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: size,
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .all
        )
        let rep = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        let img = rep.nsImage
        if let tiff = img.tiffRepresentation, let bits = NSBitmapImageRep(data: tiff),
           let png = bits.representation(using: .png, properties: [:])
        {
            try? png.write(to: cached, options: .atomic)
        }
        return img
    }

    private func cacheKey(for url: URL, size: CGSize) throws -> String {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let volumeID = (attrs[.systemNumber] as? NSNumber)?.uint64Value ?? 0
        let inode = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        let mtime = Int((attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
        return "\(volumeID)-\(inode)-\(mtime)-\(Int(size.width))x\(Int(size.height))"
    }
}
