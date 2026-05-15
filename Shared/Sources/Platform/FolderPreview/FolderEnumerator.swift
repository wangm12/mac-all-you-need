import Foundation

public enum FolderEntryKind: String, Sendable {
    case images, videos, audio, code, documents, archives, other, folder
}

public struct FolderEntry: Sendable, Equatable {
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let size: Int64
    public let modified: Date
    public let kind: FolderEntryKind
}

public struct FolderInventory: Sendable {
    public let entries: [FolderEntry]
    public let totalSize: Int64
    public let breakdown: [FolderEntryKind: Int]
    public let largest: [FolderEntry]
    public let isPartial: Bool
}

public enum FolderEnumeratorError: Error { case notADirectory }

public enum FolderEnumerator {
    public static func enumerate(
        url: URL,
        maxEntries: Int = 50000,
        includeHidden: Bool = false,
        cascade: Bool = true
    ) async throws -> FolderInventory {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw FolderEnumeratorError.notADirectory
        }
        return try await Task.detached(priority: .utility) {
            try Self.enumerateSync(
                url: url,
                maxEntries: maxEntries,
                includeHidden: includeHidden,
                cascade: cascade
            )
        }.value
    }

    public static func enumerateImmediate(url: URL, maxEntries: Int = 500, includeHidden: Bool = false) async throws -> FolderInventory {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw FolderEnumeratorError.notADirectory
        }
        return try await Task.detached(priority: .userInitiated) {
            try Self.enumerateImmediateSync(url: url, maxEntries: maxEntries, includeHidden: includeHidden)
        }.value
    }

    private static func enumerateSync(url: URL, maxEntries: Int, includeHidden: Bool, cascade: Bool) throws -> FolderInventory {
        var entries: [FolderEntry] = []
        var total: Int64 = 0
        var breakdown: [FolderEntryKind: Int] = [:]
        var partial = false

        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .nameKey]
        var options: FileManager.DirectoryEnumerationOptions = cascade ? [] : [.skipsSubdirectoryDescendants]
        if !includeHidden {
            options.insert(.skipsHiddenFiles)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: options
        ) else {
            throw FolderEnumeratorError.notADirectory
        }
        for case let item as URL in enumerator {
            if entries.count >= maxEntries { partial = true; break }
            guard let vals = try? item.resourceValues(forKeys: Set(keys)) else { continue }
            let isDir = vals.isDirectory ?? false
            if isDir, !cascade {
                enumerator.skipDescendants()
            }
            let size = Int64(vals.fileSize ?? 0)
            let kind = isDir ? FolderEntryKind.folder : Self.classify(name: item.lastPathComponent)
            entries.append(FolderEntry(
                name: item.lastPathComponent,
                path: item.path,
                isDirectory: isDir,
                size: size,
                modified: vals.contentModificationDate ?? .distantPast,
                kind: kind
            ))
            if !isDir {
                total += size
                breakdown[kind, default: 0] += 1
            }
        }
        let largest = entries.filter { !$0.isDirectory }.sorted { $0.size > $1.size }.prefix(5)
        return FolderInventory(
            entries: entries,
            totalSize: total,
            breakdown: breakdown,
            largest: Array(largest),
            isPartial: partial
        )
    }

    private static func enumerateImmediateSync(url: URL, maxEntries: Int, includeHidden: Bool) throws -> FolderInventory {
        var entries: [FolderEntry] = []
        var total: Int64 = 0
        var breakdown: [FolderEntryKind: Int] = [:]
        var partial = false

        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .nameKey]
        var options: FileManager.DirectoryEnumerationOptions = [.skipsSubdirectoryDescendants]
        if !includeHidden {
            options.insert(.skipsHiddenFiles)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: options
        ) else {
            throw FolderEnumeratorError.notADirectory
        }

        for case let item as URL in enumerator {
            if entries.count >= maxEntries {
                partial = true
                break
            }

            guard let vals = try? item.resourceValues(forKeys: Set(keys)) else { continue }
            let isDir = vals.isDirectory ?? false
            if isDir {
                enumerator.skipDescendants()
            }
            let size = Int64(vals.fileSize ?? 0)
            let kind = isDir ? FolderEntryKind.folder : Self.classify(name: item.lastPathComponent)
            entries.append(FolderEntry(
                name: item.lastPathComponent,
                path: item.path,
                isDirectory: isDir,
                size: size,
                modified: vals.contentModificationDate ?? .distantPast,
                kind: kind
            ))
            if !isDir {
                total += size
                breakdown[kind, default: 0] += 1
            }
        }

        let largest = entries.filter { !$0.isDirectory }.sorted { $0.size > $1.size }.prefix(5)
        return FolderInventory(
            entries: entries,
            totalSize: total,
            breakdown: breakdown,
            largest: Array(largest),
            isPartial: partial
        )
    }

    private static func classify(name: String) -> FolderEntryKind {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "bmp", "avif", "svg": return .images
        case "mp4", "mov", "mkv", "webm", "avi", "flv": return .videos
        case "mp3", "wav", "flac", "aac", "ogg", "m4a": return .audio
        case "swift", "py", "go", "rs", "ts", "tsx", "js", "jsx", "java", "rb", "kt", "c", "cpp", "h", "m", "mm", "sh":
            return .code
        case "pdf", "md", "txt", "doc", "docx", "rtf", "pages", "key", "numbers", "xlsx": return .documents
        case "zip", "tar", "gz", "bz2", "7z", "rar", "xz": return .archives
        default: return .other
        }
    }
}
