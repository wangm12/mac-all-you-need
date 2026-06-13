import Foundation

public final class ThumbnailCache: NSObject, NSCacheDelegate {
    /// Wraps cached data so the delegate callback can identify the owning blobID.
    private final class Entry: NSObject {
        let data: NSData
        let blobID: String
        let cacheKey: String
        init(data: NSData, blobID: String, cacheKey: String) {
            self.data = data
            self.blobID = blobID
            self.cacheKey = cacheKey
        }
    }

    private let cache = NSCache<NSString, Entry>()
    private let lock = NSLock()
    private var keysByBlob: [String: Set<String>] = [:]

    public init(totalCostLimitBytes: Int = 64 * 1024 * 1024) {
        super.init()
        cache.totalCostLimit = totalCostLimitBytes
        cache.delegate = self
    }

    public func value(blobID: String, maxDim: Int) -> Data? {
        cache.object(forKey: Self.key(blobID, maxDim) as NSString)?.data as Data?
    }

    public func set(_ data: Data, blobID: String, maxDim: Int) {
        let key = Self.key(blobID, maxDim)
        let entry = Entry(data: data as NSData, blobID: blobID, cacheKey: key)
        cache.setObject(entry, forKey: key as NSString, cost: data.count)
        lock.lock()
        keysByBlob[blobID, default: []].insert(key)
        lock.unlock()
    }

    public func remove(blobID: String) {
        lock.lock()
        let keys = keysByBlob.removeValue(forKey: blobID) ?? []
        lock.unlock()
        for key in keys {
            cache.removeObject(forKey: key as NSString)
        }
    }

    // MARK: - NSCacheDelegate

    public func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        guard let entry = obj as? Entry else { return }
        lock.lock()
        keysByBlob[entry.blobID]?.remove(entry.cacheKey)
        if keysByBlob[entry.blobID]?.isEmpty == true {
            keysByBlob.removeValue(forKey: entry.blobID)
        }
        lock.unlock()
    }

    private static func key(_ blobID: String, _ maxDim: Int) -> String {
        "\(blobID)|\(maxDim)"
    }
}
