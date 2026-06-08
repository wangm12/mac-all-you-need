import AppKit
import Foundation

/// Thread-safe per-PID window entry cache. Returns diff (added/removed/updated) on update.
@MainActor
final class DockPreviewWindowCache {
    struct Diff {
        let added: [DockPreviewWindowEntry]
        let removed: [CGWindowID]
        let updated: [DockPreviewWindowEntry]
    }

    private var cache: [pid_t: [CGWindowID: DockPreviewWindowEntry]] = [:]
    private let diskStore: DockPreviewThumbnailDiskStore?

    init(diskStore: DockPreviewThumbnailDiskStore? = nil) {
        self.diskStore = diskStore
    }

    func entries(for pid: pid_t) -> [DockPreviewWindowEntry] {
        Array(cache[pid, default: [:]].values).sorted { $0.id < $1.id }
    }

    func update(entries: [DockPreviewWindowEntry], for pid: pid_t) -> Diff {
        let old = cache[pid, default: [:]]
        let merged = entries.map { entry in
            entry.mergingCaptureMetadata(from: old[entry.id])
        }
        let newMap = Dictionary(uniqueKeysWithValues: merged.map { ($0.id, $0) })
        let added = merged.filter { old[$0.id] == nil }
        let removed = old.keys.filter { newMap[$0] == nil }
        let updated = merged.filter { entry in
            guard let previous = old[entry.id] else { return false }
            return previous != entry
        }
        cache[pid] = newMap
        return Diff(added: added, removed: Array(removed), updated: updated)
    }

    func clear(pid: pid_t) {
        cache[pid] = nil
        if let diskStore {
            Task { await diskStore.removeAll(pid: pid) }
        }
    }

    func clearAll() {
        cache = [:]
        if let diskStore {
            Task { await diskStore.removeAll() }
        }
    }

    func recordThumbnailCaptured(windowID: CGWindowID, pid: pid_t, capturedAt: Date = Date()) {
        guard var entry = cache[pid]?[windowID] else { return }
        entry.thumbnail = nil
        entry.thumbnailCapturedAt = capturedAt
        cache[pid, default: [:]][windowID] = entry
    }

    func removeFromCache(windowID: CGWindowID, pid: pid_t) {
        cache[pid]?.removeValue(forKey: windowID)
        if let diskStore {
            Task { await diskStore.remove(pid: pid, windowID: windowID) }
        }
    }

    /// Window IDs whose on-disk thumbnail is still within `lifespan` (DockDoor `freshCachedWindowIDs`).
    func freshWindowIDs(pid: pid_t, lifespan: TimeInterval, now: Date = Date()) -> Set<CGWindowID> {
        guard let diskStore, lifespan > 0 else { return [] }
        return Set(
            entries(for: pid).compactMap { entry -> CGWindowID? in
                diskStore.isFresh(pid: pid, windowID: entry.id, lifespan: lifespan, now: now) ? entry.id : nil
            }
        )
    }

    func readCached(pid: pid_t) -> [DockPreviewWindowEntry] {
        entries(for: pid)
    }
}
