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

    func entries(for pid: pid_t) -> [DockPreviewWindowEntry] {
        Array(cache[pid, default: [:]].values).sorted { $0.id < $1.id }
    }

    func update(entries: [DockPreviewWindowEntry], for pid: pid_t) -> Diff {
        let old = cache[pid, default: [:]]
        let merged = entries.map { entry in
            entry.mergingThumbnail(from: old[entry.id])
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

    func clear(pid: pid_t) { cache[pid] = nil }
    func clearAll() { cache = [:] }

    func setThumbnail(_ image: NSImage, windowID: CGWindowID, pid: pid_t) {
        guard var entry = cache[pid]?[windowID] else { return }
        entry.thumbnail = image
        cache[pid, default: [:]][windowID] = entry
    }

    func readCached(pid: pid_t) -> [DockPreviewWindowEntry] {
        entries(for: pid)
    }
}
