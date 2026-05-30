import AppKit
import Foundation

/// Caches thumbnails with a configurable TTL.
@MainActor
final class DockPreviewThumbnailCache {
    private struct Entry {
        let image: NSImage
        let timestamp: Date
    }
    private var entries: [CGWindowID: Entry] = [:]
    private let ttl: TimeInterval
    private let clock: () -> Date

    init(ttl: TimeInterval = 10.0, clock: @escaping () -> Date = { Date() }) {
        self.ttl = ttl; self.clock = clock
    }

    func get(windowID: CGWindowID) -> NSImage? {
        guard let entry = entries[windowID] else { return nil }
        if clock().timeIntervalSince(entry.timestamp) > ttl { entries[windowID] = nil; return nil }
        return entry.image
    }

    func set(windowID: CGWindowID, image: NSImage) {
        entries[windowID] = Entry(image: image, timestamp: clock())
    }

    func invalidate(windowID: CGWindowID) { entries[windowID] = nil }
    func invalidateAll() { entries = [:] }
}
