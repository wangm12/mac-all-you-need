import Foundation

/// A single recorded Finder folder visit.
public struct FolderHistoryRow: Codable, Equatable, Sendable, Identifiable {
    public let id: Int64
    public let path: String
    public var visitedAt: Date
    public var visitCount: Int
    public var isPinned: Bool
    /// Cached folder icon (PNG/TIFF data from NSWorkspace), optional.
    public var iconData: Data?

    public var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    public init(
        id: Int64 = 0,
        path: String,
        visitedAt: Date = Date(),
        visitCount: Int = 1,
        isPinned: Bool = false,
        iconData: Data? = nil
    ) {
        self.id = id
        self.path = path
        self.visitedAt = visitedAt
        self.visitCount = visitCount
        self.isPinned = isPinned
        self.iconData = iconData
    }
}
