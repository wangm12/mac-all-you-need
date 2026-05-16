import FeatureCore
import Foundation

/// Walks the directories that providers use to cache asset files and reports
/// any subdirectory that is *not* declared by the current registry's
/// `AssetCacheDescriptor`s. Used at app launch to satisfy spec Risk 9: when a
/// future release drops a Qwen3 variant, the now-unreferenced cache directory
/// would otherwise sit on disk forever.
///
/// The scanner is dependency-injected for testing; production callers use
/// `OrphanCacheScanner.makeForRegistry(_:)`.
struct OrphanCacheScanner {
    struct Orphan: Equatable {
        let url: URL
        let bytes: Int64
    }

    let scanRoots: [URL]
    let knownDirectories: () -> [URL]

    /// Returns one entry per orphan subdirectory under `scanRoots`. Each entry
    /// includes the recursive byte total so the UI can display a meaningful
    /// "Reclaim X MB" prompt.
    func scan(fileManager: FileManager = .default) -> [Orphan] {
        let known = Set(knownDirectories().map(\.standardizedFileURL.path))
        var results: [Orphan] = []
        for root in scanRoots {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            let entries = (try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for entry in entries {
                var entryIsDir: ObjCBool = false
                guard fileManager.fileExists(atPath: entry.path, isDirectory: &entryIsDir),
                      entryIsDir.boolValue
                else { continue }
                if known.contains(entry.standardizedFileURL.path) { continue }
                let bytes = recursiveBytes(at: entry, fileManager: fileManager)
                results.append(Orphan(url: entry, bytes: bytes))
            }
        }
        return results
    }

    func delete(_ orphans: [Orphan], fileManager: FileManager = .default) throws {
        for orphan in orphans {
            guard fileManager.fileExists(atPath: orphan.url.path) else { continue }
            try fileManager.removeItem(at: orphan.url)
        }
    }

    private func recursiveBytes(at url: URL, fileManager: FileManager) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    /// Production constructor: scan FluidAudio's models root (where the Qwen3
    /// provider writes today) and exclude every directory currently declared
    /// by the Voice descriptor.
    ///
    /// FluidAudio writes to ~/Library/Application Support/FluidAudio/Models/.
    /// Both Qwen3 variant directories live under that root, so a single root
    /// scan covers them all.
    static func makeForRegistry(_ registry: FeatureRegistry) -> OrphanCacheScanner {
        let voiceDescriptor = registry.descriptors.first(where: { $0.id == .voice })
        let known: [URL] = voiceDescriptor?.assetCaches.map { $0.directoryURL() } ?? []
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let modelsRoot = appSupport?
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        return OrphanCacheScanner(
            scanRoots: [modelsRoot].compactMap { $0 },
            knownDirectories: { known }
        )
    }
}
