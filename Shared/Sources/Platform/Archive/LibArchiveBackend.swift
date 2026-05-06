import CLibArchive
import Foundation

public final class LibArchiveBackend: ArchiveBackend {
    public init() {}

    public func list(archiveURL: URL, limits: ArchiveSafety.Limits) throws -> [ArchiveEntry] {
        guard let archive = archive_read_new() else { throw NSError(domain: "LibArchive", code: -1) }
        defer { archive_read_free(archive) }
        archive_read_support_format_all(archive)
        archive_read_support_filter_all(archive)
        let r = archive_read_open_filename(archive, archiveURL.path, 1024 * 64)
        guard r == ARCHIVE_OK else { throw NSError(domain: "LibArchive", code: Int(r)) }

        var entries: [ArchiveEntry] = []
        var totalSize: Int64 = 0
        var entry: OpaquePointer?
        while archive_read_next_header(archive, &entry) == ARCHIVE_OK, let e = entry {
            try ArchiveSafety.checkEntryCount(entries.count + 1, limits: limits)
            let cpath = String(cString: archive_entry_pathname(e))
            try ArchiveSafety.validatePath(cpath, limits: limits)
            let filetype = archive_entry_filetype(e)
            let isDir = filetype == 0o040000  // AE_IFDIR
            let isRegular = filetype == 0o100000  // AE_IFREG
            let isLink = archive_entry_symlink(e) != nil || archive_entry_hardlink(e) != nil
            guard isDir || (isRegular && !isLink) else {
                archive_read_data_skip(archive)
                continue
            }
            let size = archive_entry_size(e)
            try ArchiveSafety.checkPerFileSize(size, limits: limits)
            totalSize += size
            try ArchiveSafety.checkTotalUncompressed(totalSize, limits: limits)
            let mtime = Date(timeIntervalSince1970: TimeInterval(archive_entry_mtime(e)))
            entries.append(ArchiveEntry(path: cpath, isDirectory: isDir, uncompressedSize: size, modified: mtime))
            archive_read_data_skip(archive)
        }
        return entries
    }

    public func extract(archiveURL: URL, entryPath: String, to destination: URL, limits: ArchiveSafety.Limits) throws {
        try ArchiveSafety.validatePath(entryPath, limits: limits)
        guard let archive = archive_read_new() else { throw NSError(domain: "LibArchive", code: -1) }
        defer { archive_read_free(archive) }
        archive_read_support_format_all(archive)
        archive_read_support_filter_all(archive)
        let r = archive_read_open_filename(archive, archiveURL.path, 1024 * 64)
        guard r == ARCHIVE_OK else { throw NSError(domain: "LibArchive", code: Int(r)) }

        var entry: OpaquePointer?
        while archive_read_next_header(archive, &entry) == ARCHIVE_OK, let e = entry {
            let p = String(cString: archive_entry_pathname(e))
            try ArchiveSafety.validatePath(p, limits: limits)
            guard p == entryPath else { archive_read_data_skip(archive); continue }
            let filetype = archive_entry_filetype(e)
            guard filetype == 0o100000, archive_entry_symlink(e) == nil, archive_entry_hardlink(e) == nil else {
                throw NSError(domain: "LibArchive", code: 6)
            }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let out = fopen(destination.path, "wb") else { throw NSError(domain: "LibArchive", code: 5) }
            defer { fclose(out) }
            var buffer = [Int8](repeating: 0, count: 64 * 1024)
            var written: Int64 = 0
            while true {
                let n = archive_read_data(archive, &buffer, buffer.count)
                if n == 0 { break }
                if n < 0 { throw NSError(domain: "LibArchive", code: Int(n)) }
                written += Int64(n)
                try ArchiveSafety.checkPerFileSize(written, limits: limits)
                try ArchiveSafety.checkTotalUncompressed(written, limits: limits)
                guard fwrite(buffer, 1, n, out) == n else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            }
            return
        }
        throw NSError(domain: "LibArchive", code: 404)
    }
}
