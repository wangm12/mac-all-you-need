import Foundation

public enum AssetCacheCategory: String, Sendable {
    case modelWeights, databaseCache, other
}

public struct AssetCacheDescriptor: Sendable {
    public let id: String
    public let displayName: String
    public let directoryURL: @Sendable () -> URL
    public let estimatedBytes: Int64
    public let category: AssetCacheCategory

    public init(
        id: String,
        displayName: String,
        directoryURL: @escaping @Sendable () -> URL,
        estimatedBytes: Int64,
        category: AssetCacheCategory
    ) {
        self.id = id
        self.displayName = displayName
        self.directoryURL = directoryURL
        self.estimatedBytes = estimatedBytes
        self.category = category
    }

    /// Actual on-disk size, computed by walking the directory. Returns 0 if missing.
    public func actualBytes() -> Int64 {
        let url = directoryURL()
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if values?.isDirectory == true { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }
}
