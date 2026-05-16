import Foundation

/// Provider-managed asset caches (e.g., Voice's Qwen3 model files) live outside
/// wrapper-managed packs but the lifecycle still needs to read their sizes and
/// delete them on demand. This service is the single entry point for both.
public struct FeatureCacheManager {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Sum of `actualBytes()` across every cache the descriptor declares.
    /// Caches whose directory is absent contribute 0.
    public func totalBytes(for descriptor: FeatureDescriptor) -> Int64 {
        descriptor.assetCaches.reduce(into: Int64(0)) { acc, cache in
            acc += cache.actualBytes()
        }
    }

    /// Removes the named cache directories. Cache IDs that do not appear in
    /// `descriptor.assetCaches` are ignored; cache directories that don't
    /// exist on disk are no-ops. The first failure throws.
    public func deleteCaches(_ ids: [String], in descriptor: FeatureDescriptor) throws {
        let byID = Dictionary(uniqueKeysWithValues: descriptor.assetCaches.map { ($0.id, $0) })
        for id in ids {
            guard let cache = byID[id] else { continue }
            let url = cache.directoryURL()
            guard fileManager.fileExists(atPath: url.path) else { continue }
            try fileManager.removeItem(at: url)
        }
    }
}
