import Foundation

/// Persists and resolves security-scoped bookmarks for watched folders.
struct FolderBookmark {
    static func create(for url: URL) throws -> Data {
        try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resolve(_ data: Data) throws -> URL {
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale { throw FolderBookmarkError.stale }
        return url
    }

    enum FolderBookmarkError: Error { case stale }
}
