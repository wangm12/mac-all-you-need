import Foundation

public final class ThumbnailCache {
    private let cache = NSCache<NSString, NSData>()
    private let lock = NSLock()
    private var keysByBlob: [String: Set<String>] = [:]

    public init(totalCostLimitBytes: Int = 64 * 1024 * 1024) {
        cache.totalCostLimit = totalCostLimitBytes
    }

    public func value(blobID: String, maxDim: Int) -> Data? {
        cache.object(forKey: Self.key(blobID, maxDim) as NSString) as Data?
    }

    public func set(_ data: Data, blobID: String, maxDim: Int) {
        let key = Self.key(blobID, maxDim)
        cache.setObject(data as NSData, forKey: key as NSString, cost: data.count)
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

    private static func key(_ blobID: String, _ maxDim: Int) -> String {
        "\(blobID)|\(maxDim)"
    }
}
