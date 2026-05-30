import Foundation

/// Pure retention policy for folder history rows.
public enum FolderHistoryRetention {
    /// Given rows sorted by recency (newest first), returns the IDs to evict so that
    /// at most `maxCount` unpinned rows remain. Pinned rows are exempt and never evicted.
    public static func evictIDs(
        rows: [(id: Int64, isPinned: Bool)],
        maxCount: Int
    ) -> [Int64] {
        let unpinned = rows.filter { !$0.isPinned }
        guard unpinned.count > maxCount else { return [] }
        return Array(unpinned.suffix(unpinned.count - maxCount).map { $0.id })
    }
}
