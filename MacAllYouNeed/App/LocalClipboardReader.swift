import Core
import Foundation

@MainActor
@Observable
final class LocalClipboardReader {
    private(set) var items: [ClipboardItemMeta] = []
    private var query: String = ""
    /// Exposed so other read paths (e.g. the dock) can share this store rather
    /// than opening a second DatabaseQueue against the same SQLite file.
    let store: ClipboardStore?
    private var pollTask: Task<Void, Never>?
    private var changeObserver: NSObjectProtocol?

    init(store: ClipboardStore) {
        self.store = store
        startPolling()
        // Reload immediately whenever the dock model mutates the store
        // (delete, rename, retention) so the menu bar popover stays in
        // sync without waiting up to a full poll interval. The observer
        // captures `weak self` and is collected with the reader; we don't
        // need an explicit removeObserver in deinit.
        changeObserver = NotificationCenter.default.addObserver(
            forName: .clipboardStoreDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.reload() }
        }
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
            try? await Task.sleep(for: .milliseconds(300))
            while !Task.isCancelled {
                await reload()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func reload() async {
        guard let store else { return }
        let currentQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await Task.detached(priority: .userInitiated) {
            Result { try store.list(limit: 200) }
        }.value
        switch result {
        case .success(let fetched):
            let deduped = Self.deduplicate(fetched, limit: 30)
            if currentQuery.isEmpty {
                items = deduped
            } else {
                let lower = currentQuery.lowercased()
                items = deduped.filter { $0.preview.lowercased().contains(lower) }
            }
        case .failure:
            items = []
        }
    }

    /// One copy action often writes multiple records (image + file URL, RTF + plain text).
    /// Group items within a 0.5s window and keep the most informative one per group.
    private static func deduplicate(_ sorted: [ClipboardItemMeta], limit: Int) -> [ClipboardItemMeta] {
        var result: [ClipboardItemMeta] = []
        for item in sorted {
            if let last = result.last,
               abs(last.modified.timeIntervalSince(item.modified)) < 0.5
            {
                // Same copy action — keep the more informative item
                if previewPriority(item.preview) > previewPriority(last.preview) {
                    result[result.count - 1] = item
                }
            } else {
                result.append(item)
            }
            if result.count >= limit { break }
        }
        return result
    }

    /// Higher = more informative. Text > Image > File list
    private static func previewPriority(_ preview: String) -> Int {
        if preview.hasPrefix("(image ") { return 1 }
        if preview.hasPrefix("(") && preview.contains("file") { return 0 }
        return 2
    }
}

extension Notification.Name {
    /// Posted by any in-process mutation of the shared ClipboardStore (dock
    /// delete, rename, local retention) so other readers (menu bar popover)
    /// reload immediately instead of waiting up to a full poll interval.
    static let clipboardStoreDidChange = Notification.Name("clipboardStoreDidChange")
}
