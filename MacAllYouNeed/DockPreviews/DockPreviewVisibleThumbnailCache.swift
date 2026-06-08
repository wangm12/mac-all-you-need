import AppKit
import Foundation

/// Bounded in-memory LRU for thumbnails currently shown in the dock preview / switcher strip.
@MainActor
final class DockPreviewVisibleThumbnailCache {
    static let maxEntries = 16

    private let diskStore: DockPreviewThumbnailDiskStore
    private struct CacheKey: Hashable {
        let pid: pid_t
        let windowID: CGWindowID
    }

    private var images: [CacheKey: NSImage] = [:]
    private var order: [CacheKey] = []

    init(diskStore: DockPreviewThumbnailDiskStore) {
        self.diskStore = diskStore
    }

    func hydrate(_ entries: [DockPreviewWindowEntry]) -> [DockPreviewWindowEntry] {
        var lruHits = 0
        var diskLoads = 0
        var misses = 0

        let hydrated = entries.map { entry -> DockPreviewWindowEntry in
            var copy = entry
            switch resolveImage(for: entry) {
            case .lruHit(let image):
                lruHits += 1
                copy.thumbnail = image
            case .diskLoad(let image):
                diskLoads += 1
                copy.thumbnail = image
            case .miss:
                misses += 1
                copy.thumbnail = nil
            }
            return copy
        }

        if !entries.isEmpty {
            DockPreviewThumbnailDiagnostics.lruHydrate(
                entries: entries.count,
                lruHits: lruHits,
                diskLoads: diskLoads,
                misses: misses,
                resident: images.count
            )
        }
        return hydrated
    }

    func evictAll() {
        let before = images.count
        images.removeAll()
        order.removeAll()
        if before > 0 {
            DockPreviewThumbnailDiagnostics.lruEvict(residentBefore: before)
        }
    }

    private enum ImageSource {
        case lruHit(NSImage)
        case diskLoad(NSImage)
        case miss
    }

    private func resolveImage(for entry: DockPreviewWindowEntry) -> ImageSource {
        let key = CacheKey(pid: entry.pid, windowID: entry.id)
        if let cached = images[key] {
            touch(key)
            return .lruHit(cached)
        }
        if let prefetched = entry.thumbnail {
            insert(prefetched, key: key)
            return .diskLoad(prefetched)
        }
        // Sync load only when a JPEG already exists — avoids `panel.show` flashing empty before async hydrate.
        if diskStore.hasThumbnail(pid: entry.pid, windowID: entry.id),
           let image = diskStore.loadImage(pid: entry.pid, windowID: entry.id, title: entry.title)
        {
            insert(image, key: key)
            return .diskLoad(image)
        }
        return .miss
    }

    private func insert(_ image: NSImage, key: CacheKey) {
        images[key] = image
        touch(key)
        while order.count > Self.maxEntries, let oldest = order.first {
            images.removeValue(forKey: oldest)
            order.removeFirst()
        }
    }

    private func touch(_ key: CacheKey) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
