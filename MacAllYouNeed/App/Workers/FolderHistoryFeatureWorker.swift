import Core
import FeatureCore
import Foundation

/// Folder-history GRDB writes and retention eviction off the main actor.
actor FolderHistoryFeatureWorker: FeatureWorker {
    private var isRunning = false

    func start() async {
        guard !isRunning else { return }
        isRunning = true
    }

    func stop() async {
        isRunning = false
    }

    func persistVisit(
        store: FolderHistoryStore,
        path: String,
        retentionMax: Int,
        now: Date
    ) async throws -> Bool {
        guard isRunning else { return false }
        try await Task.detached {
            _ = try store.upsert(path: path, now: now)
            try store.evictStale(maxCount: retentionMax)
        }.value
        return true
    }
}
