import AppKit
import Core
import Foundation
import Platform

@MainActor
@Observable
final class LocalClipboardReader {
    private(set) var items: [ClipboardItemMeta] = []
    private var query: String = ""
    /// Exposed so other read paths (e.g. the dock) can share this store rather
    /// than opening a second DatabaseQueue against the same SQLite file.
    let store: ClipboardStore?
    /// Optional blob store — used by the suppression filter to clean up image
    /// blobs of records the daemon re-captured after a user-initiated delete.
    weak var blobsRef: BlobStore?
    /// Multi-select state for the menu-bar clipboard tab. Lives here (a class)
    /// so NSEvent monitors can capture `reader` and read live values — capturing
    /// `@State` from a SwiftUI struct gives a stale snapshot.
    var selectedIDs: Set<String> = []
    var anchorID: String? = nil
    /// Previews of items the user just deleted via the menu bar. The daemon
    /// would otherwise re-capture them immediately (the content is still on
    /// the system clipboard), making deletion look like it didn't work.
    /// Entries expire after `deleteSuppressionWindow` so genuine re-copies
    /// later still appear.
    private var recentlyDeletedPreviews: [String: Date] = [:]
    private static let deleteSuppressionWindow: TimeInterval = 15
    private var pbSuppressionTask: Task<Void, Never>? = nil
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

    /// Mark a preview as just-deleted. While the entry is fresh, any new item
    /// the daemon adds with the same preview is auto-deleted instead of shown.
    func markDeleted(preview: String) {
        recentlyDeletedPreviews[preview] = Date()
        pruneRecentlyDeleted()
    }

    /// Returns all records whose `modified` falls within `within` seconds of
    /// the given record's. The daemon writes one record per pasteboard
    /// representation (a single screenshot copy yields .png + .tiff + .fileURL,
    /// i.e. three records — and large image blobs may be spread over hundreds of
    /// ms due to disk I/O during blob writes). Without this, the dedup hides
    /// them but deleting one leaves the others visible.
    func relatedItems(toID id: String, within: TimeInterval = 2.0) -> [ClipboardItemMeta] {
        guard let store else { return [] }
        guard let target = items.first(where: { $0.id.rawValue == id }) else { return [] }
        let window = ClipboardHistoryWindow.listParameters()
        let all = (try? store.list(limit: 200, modifiedOnOrAfter: window.modifiedOnOrAfter)) ?? []
        return all.filter { abs($0.modified.timeIntervalSince(target.modified)) < within }
    }

    /// Run a brief pasteboard watcher that re-clears if ANY non-sentinel
    /// content reappears while we're suppressing. Some apps (CleanShot,
    /// screenshot tools, image editors, file managers) re-assert pasteboard
    /// ownership and write content back after we clear — defeating the
    /// daemon-write sentinel. This watcher catches that and clears again
    /// until they stop, for the duration of the suppression window.
    func startRewriteSuppression() {
        pbSuppressionTask?.cancel()
        pbSuppressionTask = Task { @MainActor in
            let pb = NSPasteboard.general
            var lastCount = pb.changeCount
            let deadline = Date().addingTimeInterval(Self.deleteSuppressionWindow)
            while Date() < deadline {
                try? await Task.sleep(for: .milliseconds(120))
                if Task.isCancelled { return }
                pruneRecentlyDeleted()
                if recentlyDeletedPreviews.isEmpty { return }
                let cur = pb.changeCount
                guard cur != lastCount else { continue }
                lastCount = cur
                let types = pb.types ?? []
                // Skip our own writes (sentinel present) — those are us re-clearing.
                if types.contains(PasteboardUTI.daemonWrite) { continue }
                // Anything else came from an external app (CleanShot, etc.) — wipe it.
                pb.clearContents()
                pb.declareTypes([PasteboardUTI.daemonWrite], owner: nil)
                pb.setData(Data([0]), forType: PasteboardUTI.daemonWrite)
                lastCount = pb.changeCount
            }
        }
    }

    private func pruneRecentlyDeleted() {
        let cutoff = Date().addingTimeInterval(-Self.deleteSuppressionWindow)
        recentlyDeletedPreviews = recentlyDeletedPreviews.filter { $0.value >= cutoff }
    }

    private func isSuppressed(preview: String) -> Bool {
        guard let when = recentlyDeletedPreviews[preview] else { return false }
        return when >= Date().addingTimeInterval(-Self.deleteSuppressionWindow)
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
            let window = ClipboardHistoryWindow.listParameters()
            return Result { try store.list(limit: 200, modifiedOnOrAfter: window.modifiedOnOrAfter) }
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
    static func deduplicate(_ sorted: [ClipboardItemMeta], limit: Int) -> [ClipboardItemMeta] {
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
