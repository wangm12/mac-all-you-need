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
    let search: SearchStore?
    let worker: ClipboardWorker?
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
    static let deleteSuppressionWindow: TimeInterval = 15
    private var pbSuppressionTask: Task<Void, Never>? = nil
    private var pollTask: Task<Void, Never>?
    private var changeObserver: NSObjectProtocol?

    init(store: ClipboardStore, search: SearchStore? = nil, worker: ClipboardWorker? = nil) {
        self.store = store
        self.search = search
        self.worker = worker
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

    func resumePolling() {
        guard pollTask == nil else { return }
        startPolling()
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
        let result: Result<[ClipboardItemMeta], Error>
        if let worker {
            let loaded = await worker.loadForReader(query: currentQuery)
            result = .success(loaded)
        } else {
            let searchStore = search
            result = await Task.detached(priority: .userInitiated) {
                let window = ClipboardHistoryWindow.listParameters()
                return Result {
                    if currentQuery.isEmpty {
                        return try store.list(limit: 200, modifiedOnOrAfter: window.modifiedOnOrAfter)
                    }
                    if SmartSearchQuery(currentQuery).hasOperators {
                        let recent = try store.list(limit: 200, modifiedOnOrAfter: window.modifiedOnOrAfter)
                        return Self.applyQuery(currentQuery, to: recent)
                    }
                    return try ClipboardHistoryQueryLoader.load(
                        clip: store,
                        search: searchStore,
                        query: currentQuery,
                        limit: 90,
                        modifiedOnOrAfter: window.modifiedOnOrAfter
                    )
                }
            }.value
        }
        switch result {
        case .success(let fetched):
            pruneRecentlyDeleted()
            let visible = applyDeleteSuppression(to: fetched)
            items = Self.deduplicate(visible, limit: 30)
        case .failure:
            items = []
        }
    }

    private func applyDeleteSuppression(to fetched: [ClipboardItemMeta]) -> [ClipboardItemMeta] {
        guard !recentlyDeletedPreviews.isEmpty else { return fetched }
        var suppressedIDs: [RecordID] = []
        let visible = fetched.filter { item in
            guard isSuppressed(preview: item.preview) else { return true }
            suppressedIDs.append(item.id)
            return false
        }
        if let store, !suppressedIDs.isEmpty {
            for id in suppressedIDs {
                try? store.delete(id: id)
            }
            NotificationCenter.default.post(name: .clipboardStoreDidChange, object: nil)
        }
        return visible
    }

    /// Applies the smart search query to popover items, matching the dock's
    /// predicate semantics: app include/exclude, type (OR), date lower bound,
    /// and free-text / regex over preview + OCR text. Falls back to a plain
    /// substring match when no smart operators are present.
    nonisolated static func applyQuery(_ query: String, to metas: [ClipboardItemMeta]) -> [ClipboardItemMeta] {
        let smart = SmartSearchQuery(query)
        guard smart.hasOperators else {
            let lower = query.lowercased()
            return metas.filter { $0.preview.lowercased().contains(lower) }
        }
        return metas.filter { meta in
            let appID = (meta.sourceAppBundleID ?? "").lowercased()
            if !smart.appFilters.isEmpty {
                guard smart.appFilters.contains(where: appID.contains) else { return false }
            }
            if !smart.negatedApps.isEmpty {
                if smart.negatedApps.contains(where: appID.contains) { return false }
            }
            if !smart.typeFilters.isEmpty {
                let type = Self.detectedTypeName(meta) ?? "plain"
                guard smart.typeFilters.contains(type) else { return false }
            }
            if let lower = smart.dateOnOrAfter, meta.modified < lower { return false }
            return smart.matchesText(meta.preview, ocrText: meta.ocrText)
        }
    }

    nonisolated private static func detectedTypeName(_ meta: ClipboardItemMeta) -> String? {
        guard let json = meta.detectedTypeJSON,
              let detection = try? Detection.decode(json: json) else { return nil }
        switch detection.type {
        case .plain: return "plain"
        case .email: return "email"
        case .url: return "url"
        case .phone: return "phone"
        case .jwt: return "jwt"
        case .color: return "color"
        case .code: return "code"
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
