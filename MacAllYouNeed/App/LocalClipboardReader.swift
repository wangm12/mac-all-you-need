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
        reload()
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.reload()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func reload() {
        guard let store else {
            NSLog("📋 LocalClipboardReader: store is nil")
            return
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let fetched = try store.list(limit: 50)
            NSLog("📋 LocalClipboardReader: fetched \(fetched.count) items")
            if trimmed.isEmpty {
                items = fetched
            } else {
                let lower = trimmed.lowercased()
                items = fetched.filter { $0.preview.lowercased().contains(lower) }
            }
        } catch {
            NSLog("📋 LocalClipboardReader: list() threw: \(error)")
            items = []
        }
    }
}
