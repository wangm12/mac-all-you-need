import FeatureCore
import Foundation
import Platform

/// Folder browse / libarchive listing off the main actor.
actor FolderPreviewFeatureWorker: FeatureWorker {
    private var isRunning = false

    func start() async {
        guard !isRunning else { return }
        isRunning = true
    }

    func stop() async {
        isRunning = false
    }

    /// Runs folder/archive listing or analyze scans off the main actor.
    func loadListing<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        guard isRunning else { return try await operation() }
        return try await operation()
    }

    func enumerate(_ request: FolderListingRequest) async throws -> FolderInventory {
        try await loadListing {
            try await FolderEnumerator.enumerate(
                url: request.url,
                maxEntries: request.maxEntries,
                includeHidden: request.includeHidden,
                cascade: request.cascade
            )
        }
    }
}
