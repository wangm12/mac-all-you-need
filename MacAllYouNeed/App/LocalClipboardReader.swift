import Core
import Foundation

@MainActor
@Observable
final class LocalClipboardReader {
    private(set) var items: [ClipboardItemMeta] = []
    private var query: String = ""
    private var store: ClipboardStore?
    private var pollTask: Task<Void, Never>?

    init(store: ClipboardStore) {
        self.store = store
        startPolling()
    }

    func search(query: String) {
        self.query = query
        Task { await reload() }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func startPolling() {
        pollTask = Task {
            // Small initial delay to let the daemon finish any in-flight write
            try? await Task.sleep(for: .milliseconds(300))
            while !Task.isCancelled {
                await reload()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func reload() async {
        guard let store else {
            NSLog("📋 LocalClipboardReader: store is nil")
            return
        }
        let currentQuery = query
        let trimmed = currentQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        // Run the DB read on a background thread to avoid blocking the main actor
        let result = await Task.detached(priority: .userInitiated) {
            Result { try store.list(limit: 50) }
        }.value
        switch result {
        case .success(let fetched):
            NSLog("📋 LocalClipboardReader: fetched \(fetched.count) items")
            if trimmed.isEmpty {
                items = fetched
            } else {
                let lower = trimmed.lowercased()
                items = fetched.filter { $0.preview.lowercased().contains(lower) }
            }
        case .failure(let error):
            NSLog("📋 LocalClipboardReader: list() threw: \(error)")
            items = []
        }
    }
}
