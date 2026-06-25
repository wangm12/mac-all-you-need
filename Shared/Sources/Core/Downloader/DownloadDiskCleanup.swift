import Foundation

public enum DownloadDiskCleanup {
    public static func isConcretePath(_ path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("%(")
    }

    public static func deleteArtifacts(at path: String) {
        guard isConcretePath(path) else { return }
        let fileManager = FileManager.default
        for candidate in [path, path + ".part", path + ".ytdl"] {
            if fileManager.fileExists(atPath: candidate) {
                try? fileManager.removeItem(atPath: candidate)
            }
        }
    }

    /// Resolves the on-disk folder for any grouped download batch (YouTube playlist,
    /// Douyin profile folder, multi-URL collection) when collection subfolders are enabled.
    public static func collectionFolderURL(for records: [DownloadRecord]) -> URL? {
        guard let first = records.first else { return nil }
        let collectionTitle = first.collectionTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !collectionTitle.isEmpty else { return nil }
        let useSubfolder = AppGroupSettings.defaults
            .object(forKey: "downloadCollectionSubfolder") as? Bool ?? true
        guard useSubfolder else { return nil }
        return try? DownloadDestinationBuilder.outputDirectory(
            collectionTitle: collectionTitle,
            useCollectionSubfolder: true
        )
    }

    /// Derives the shared on-disk folder from persisted destination paths, including
    /// yt-dlp templates like `.../Playlist/%(title)s.%(ext)s`.
    public static func inferredCollectionFolder(from paths: [String]) -> URL? {
        let parents: [URL] = paths
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0).deletingLastPathComponent().standardizedFileURL }
        guard let first = parents.first, !parents.isEmpty else { return nil }
        guard parents.allSatisfy({ $0 == first }) else { return nil }
        guard !isBaseDownloadDirectory(first) else { return nil }
        return first
    }

    public static func resolvedCollectionFolder(
        paths: [String],
        records: [DownloadRecord]
    ) -> URL? {
        if let inferred = inferredCollectionFolder(from: paths) {
            return inferred
        }
        return collectionFolderURL(for: records)?.standardizedFileURL
    }

    public static func deleteFiles(for records: [DownloadRecord]) {
        let paths = records.map(\.destinationPath)
        deleteFiles(atPaths: paths, collectionRecords: records)
    }

    public static func deleteFiles(atPaths paths: [String], collectionRecords: [DownloadRecord]) {
        var seenPaths = Set<String>()
        for path in paths where isConcretePath(path) && seenPaths.insert(path).inserted {
            deleteArtifacts(at: path)
        }
        guard let folder = resolvedCollectionFolder(paths: paths, records: collectionRecords) else { return }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: folder.path) else { return }
        try? fileManager.removeItem(at: folder)
    }

    private static func isBaseDownloadDirectory(_ url: URL) -> Bool {
        guard let base = try? DownloadDestinationBuilder.outputDirectory(
            collectionTitle: nil,
            useCollectionSubfolder: false
        ) else {
            return false
        }
        return url.standardizedFileURL.path == base.standardizedFileURL.path
    }
}
