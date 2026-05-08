import Foundation

public struct RetentionPolicy: Sendable {
    public let maxItems: Int?
    public let maxAgeSeconds: TimeInterval?
    public let maxImageBytes: Int?

    public init(maxItems: Int?, maxAgeSeconds: TimeInterval?, maxImageBytes: Int?) {
        self.maxItems = maxItems
        self.maxAgeSeconds = maxAgeSeconds
        self.maxImageBytes = maxImageBytes
    }

    /// Cap semantics: protected items do not count against the cap.
    public func enforceItemCap(
        store: ClipboardStore,
        blobs: BlobStore,
        protectedIDs: Set<RecordID>
    ) throws {
        guard let cap = maxItems else { return }
        let all = try store.list(limit: 10_000)
        let candidates = all.filter { !protectedIDs.contains($0.id) }
        let overflow = max(0, candidates.count - cap)
        guard overflow > 0 else { return }

        // list() returns newest first, so overflow victims are at the tail.
        for victim in candidates.suffix(overflow) {
            try Self.deleteWithBlob(victim.id, store: store, blobs: blobs)
        }
    }

    public func enforceMaxAge(
        store: ClipboardStore,
        blobs: BlobStore,
        protectedIDs: Set<RecordID>,
        now: Date = Date()
    ) throws {
        guard let maxAgeSeconds else { return }
        let cutoff = now.addingTimeInterval(-maxAgeSeconds)
        let all = try store.list(limit: 10_000)
        for meta in all where meta.modified < cutoff && !protectedIDs.contains(meta.id) {
            try Self.deleteWithBlob(meta.id, store: store, blobs: blobs)
        }
    }

    public func enforceImageCap(
        store: ClipboardStore,
        blobs: BlobStore,
        protectedIDs: Set<RecordID>
    ) throws {
        guard let maxImageBytes else { return }

        var imageEntries: [(id: RecordID, blobID: String, modified: Date, bytes: Int)] = []
        for meta in try store.list(limit: 10_000) where !protectedIDs.contains(meta.id) {
            guard case let .image(blobID, _, _) = try store.body(for: meta.id) else { continue }
            let size = encryptedBlobSize(blobs: blobs, blobID: blobID)
            imageEntries.append((meta.id, blobID, meta.modified, size))
        }

        var totalBytes = imageEntries.reduce(0) { $0 + $1.bytes }
        guard totalBytes > maxImageBytes else { return }

        // Evict oldest images first.
        for entry in imageEntries.sorted(by: { $0.modified < $1.modified }) {
            try? blobs.delete(id: entry.blobID)
            try store.delete(id: entry.id)
            totalBytes -= entry.bytes
            if totalBytes <= maxImageBytes {
                return
            }
        }
    }

    /// Removes image blob files alongside record rows to avoid orphan blobs.
    private static func deleteWithBlob(
        _ id: RecordID,
        store: ClipboardStore,
        blobs: BlobStore
    ) throws {
        if let body = try? store.body(for: id), case let .image(blobID, _, _) = body {
            try? blobs.delete(id: blobID)
        }
        try store.delete(id: id)
    }

    private func encryptedBlobSize(blobs: BlobStore, blobID: String) -> Int {
        let url = blobs.encryptedURL(id: blobID)
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? 0
    }
}

public extension PinboardStore {
    static func protectedIDs(from store: PinboardStore) throws -> Set<RecordID> {
        try store.list().reduce(into: Set<RecordID>()) { set, board in
            board.itemIDs.forEach { set.insert($0) }
        }
    }
}
