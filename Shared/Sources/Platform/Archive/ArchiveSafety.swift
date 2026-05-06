import Foundation

public enum ArchiveSafetyError: Error, Equatable {
    case absolutePath, pathTraversal, tooDeep
    case tooManyEntries, tooLargeUncompressed, perFileTooLarge
    case symlinkInPreview
}

public enum ArchiveSafety {
    public struct Limits: Sendable {
        public var maxEntries: Int
        public var maxDepth: Int
        public var maxTotalUncompressedBytes: Int64
        public var maxPerFileBytes: Int64
        public static let `default` = Limits(
            maxEntries: 50_000,
            maxDepth: 64,
            maxTotalUncompressedBytes: 5 * 1024 * 1024 * 1024,
            maxPerFileBytes: 1 * 1024 * 1024 * 1024
        )
    }

    public static func validatePath(_ path: String, limits: Limits) throws {
        if path.hasPrefix("/") { throw ArchiveSafetyError.absolutePath }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        var depth = 0
        for p in parts {
            if p == ".." { throw ArchiveSafetyError.pathTraversal }
            if p == "." || p.isEmpty { continue }
            depth += 1
            if depth > limits.maxDepth { throw ArchiveSafetyError.tooDeep }
        }
    }

    public static func checkEntryCount(_ count: Int, limits: Limits) throws {
        if count > limits.maxEntries { throw ArchiveSafetyError.tooManyEntries }
    }

    public static func checkTotalUncompressed(_ bytes: Int64, limits: Limits) throws {
        if bytes > limits.maxTotalUncompressedBytes { throw ArchiveSafetyError.tooLargeUncompressed }
    }

    public static func checkPerFileSize(_ bytes: Int64, limits: Limits) throws {
        if bytes > limits.maxPerFileBytes { throw ArchiveSafetyError.perFileTooLarge }
    }
}
