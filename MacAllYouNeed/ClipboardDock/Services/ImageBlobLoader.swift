import AppKit
import Core
import Foundation

actor ImageBlobLoader {
    private let xpc: any ClipboardXPCInteracting
    private let cache = NSCache<NSString, NSImage>()

    init(xpc: any ClipboardXPCInteracting, totalCostLimitBytes: Int = 64 * 1024 * 1024) {
        self.xpc = xpc
        cache.totalCostLimit = totalCostLimitBytes
    }

    func thumbnail(recordID: String, maxDim: Int) async -> NSImage? {
        let key = "\(recordID)|\(maxDim)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = await xpc.imageThumbnail(forID: recordID, maxDim: maxDim),
              let image = NSImage(data: data) else {
            return nil
        }
        cache.setObject(image, forKey: key, cost: data.count)
        return image
    }
}
