import Foundation

/// Request to enumerate a folder for the Browse Folder window.
public struct FolderListingRequest: Sendable {
    public let url: URL
    public let maxEntries: Int
    public let includeHidden: Bool
    public let cascade: Bool

    public init(url: URL, maxEntries: Int, includeHidden: Bool, cascade: Bool) {
        self.url = url
        self.maxEntries = maxEntries
        self.includeHidden = includeHidden
        self.cascade = cascade
    }
}

/// Optional hook so the main app can route folder scans through `FolderPreviewFeatureWorker`.
public enum FolderPreviewListing {
    public typealias Loader = @Sendable (FolderListingRequest) async throws -> FolderInventory

    private static let lock = NSLock()
    private static var loader: Loader?

    public static func install(loader: Loader?) {
        lock.lock()
        defer { lock.unlock() }
        self.loader = loader
    }

    public static func enumerate(
        url: URL,
        maxEntries: Int = 50000,
        includeHidden: Bool = false,
        cascade: Bool = true
    ) async throws -> FolderInventory {
        let request = FolderListingRequest(
            url: url,
            maxEntries: maxEntries,
            includeHidden: includeHidden,
            cascade: cascade
        )
        lock.lock()
        let active = loader
        lock.unlock()
        if let active {
            return try await active(request)
        }
        return try await FolderEnumerator.enumerate(
            url: url,
            maxEntries: maxEntries,
            includeHidden: includeHidden,
            cascade: cascade
        )
    }
}
