import Foundation

public struct ArchiveEntry: Equatable, Sendable {
    public let path: String
    public let isDirectory: Bool
    public let uncompressedSize: Int64
    public let modified: Date?
}

public protocol ArchiveBackend: AnyObject {
    func list(archiveURL: URL, limits: ArchiveSafety.Limits) throws -> [ArchiveEntry]
    func extract(archiveURL: URL, entryPath: String, to destination: URL, limits: ArchiveSafety.Limits) throws
}
