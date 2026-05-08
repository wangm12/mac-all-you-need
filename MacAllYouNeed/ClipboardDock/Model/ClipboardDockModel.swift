import Core
import Foundation
import Observation
import Platform

@MainActor
@Observable
final class ClipboardDockModel {
    let xpc: any ClipboardXPCInteracting
    let appIcons: AppIconResolver
    let imageLoader: ImageBlobLoader
    let fileLoader: FileURLLoader
    let pinboards: PinboardStore
    let snippets: SnippetStore
    /// Optional in-process read path. When non-nil, the History tab reads
    /// directly from the encrypted SQLite store the daemon writes to (same
    /// path the menu-bar popover uses) instead of going through XPC. This
    /// keeps the dock populated when the daemon's mach service registration
    /// fails — a known macOS Sequoia issue with SMAppService.loginItem.
    /// Writes (paste/delete/transform) still go through XPC.
    let clip: ClipboardStore?

    var items: [DockItem] = []
    var snippetItems: [Snippet] = []
    var search: String = ""
    var focusedIndex: Int = 0
    var activeList: DockListSelector = .history
    var availableLists: [Pinboard] = []
    var selection: Set<DockItem.ID> = []
    var isQuickLooking: Bool = false
    var pendingTransform: TextTransform?
    var showTransformMenu: Bool = false
    var showCheatsheet: Bool = false

    private var refreshDebounceTask: Task<Void, Never>?
    private var refreshSequence: UInt64 = 0

    init(
        xpc: any ClipboardXPCInteracting,
        appIcons: AppIconResolver,
        imageLoader: ImageBlobLoader,
        fileLoader: FileURLLoader,
        pinboards: PinboardStore,
        snippets: SnippetStore,
        clip: ClipboardStore? = nil
    ) {
        self.xpc = xpc
        self.appIcons = appIcons
        self.imageLoader = imageLoader
        self.fileLoader = fileLoader
        self.pinboards = pinboards
        self.snippets = snippets
        self.clip = clip
    }

    func loadAvailableLists() async {
        availableLists = PinnedPinboard.userVisibleLists((try? pinboards.list()) ?? [])
    }

    func switchList(_ selector: DockListSelector) async {
        activeList = selector
        search = ""
        focusedIndex = 0
        await refresh()
    }

    func refresh() async {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = nil
        let sequence = nextRefreshSequence()
        await performRefresh(sequence: sequence)
    }

    func refreshDebounced() {
        refreshDebounceTask?.cancel()
        let sequence = nextRefreshSequence()
        refreshDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            await self?.performRefresh(sequence: sequence)
        }
    }

    func togglePin(itemID: String) async {
        guard let recordID = RecordID(rawValue: itemID),
              let pinnedID = try? PinnedPinboard.findOrCreate(in: pinboards).id
        else { return }

        // Atomic read-modify-write so concurrent toggles do not lose updates.
        try? pinboards.mutate(id: pinnedID) { board in
            if board.itemIDs.contains(recordID) {
                board.itemIDs.removeAll { $0 == recordID }
            } else {
                board.itemIDs.append(recordID)
            }
        }

        if activeList == .pinned || activeList == .history {
            await refresh()
        }
    }

    func addToPinboard(itemIDs: [String], boardID: RecordID) async {
        let recordIDs = itemIDs.compactMap(RecordID.init(rawValue:))
        guard !recordIDs.isEmpty else { return }
        try? pinboards.mutate(id: boardID) { board in
            for rid in recordIDs where !board.itemIDs.contains(rid) {
                board.itemIDs.append(rid)
            }
        }
    }

    func focusForward() {
        guard !items.isEmpty else { return }
        focusedIndex = min(items.count - 1, focusedIndex + 1)
    }

    func focusBackward() {
        guard !items.isEmpty else { return }
        focusedIndex = max(0, focusedIndex - 1)
    }

    func toggleSelection(itemID: String) {
        if selection.contains(itemID) {
            selection.remove(itemID)
        } else {
            selection.insert(itemID)
        }
    }

    func extendSelectionRight() {
        guard items.indices.contains(focusedIndex) else { return }
        selection.insert(items[focusedIndex].id)
        let nextIndex = focusedIndex + 1
        guard items.indices.contains(nextIndex) else { return }
        focusedIndex = nextIndex
        selection.insert(items[nextIndex].id)
    }

    func extendSelectionLeft() {
        guard items.indices.contains(focusedIndex) else { return }
        selection.insert(items[focusedIndex].id)
        let previousIndex = focusedIndex - 1
        guard items.indices.contains(previousIndex) else { return }
        focusedIndex = previousIndex
        selection.insert(items[previousIndex].id)
    }

    func clearSelection() {
        selection.removeAll()
    }

    func selectAllVisible() {
        selection = Set(items.prefix(50).map(\.id))
    }

    func pasteSelectionInOrder(delimiter: String, plainText: Bool) async {
        let orderedIDs = items.map(\.id).filter { selection.contains($0) }
        guard !orderedIDs.isEmpty else { return }
        _ = await xpc.pasteMany(itemIDs: orderedIDs, delimiter: delimiter, plainText: plainText)
    }

    func deleteSelected() async {
        let ids = Array(selection)
        for id in ids {
            _ = await xpc.deleteItem(id: id)
        }
        clearSelection()
        await refresh()
    }

    func applyTransform(_ transform: TextTransform, saveAsNew: Bool) async {
        let targets: [String]
        if !selection.isEmpty {
            targets = items.map(\.id).filter { selection.contains($0) }
        } else if items.indices.contains(focusedIndex) {
            targets = [items[focusedIndex].id]
        } else {
            return
        }

        pendingTransform = transform
        for id in targets {
            _ = await xpc.transformAndCopy(
                itemID: id,
                transform: transform.rawValue,
                saveAsNew: saveAsNew
            )
        }
        pendingTransform = nil
        await refresh()
    }

    func loadSnippets() async {
        snippetItems = (try? snippets.list()) ?? []
    }

    func createSnippet(name: String, body: String, trigger: String?) async throws {
        try snippets.create(name: name, body: body, trigger: trigger)
        await loadSnippets()
    }

    func updateSnippet(id: RecordID, name: String, body: String, trigger: String?) async throws {
        try snippets.update(id: id, name: name, body: body, trigger: trigger)
        await loadSnippets()
    }

    func deleteSnippet(id: RecordID) async {
        try? snippets.delete(id: id)
        await loadSnippets()
    }

    func duplicateSnippet(id: RecordID) async {
        guard let original = snippetItems.first(where: { $0.id == id }) else { return }
        _ = try? snippets.create(
            name: "\(original.name) (copy)",
            body: original.body,
            trigger: nil
        )
        await loadSnippets()
    }

    func pasteSnippet(id: RecordID, plainText: Bool) async {
        guard let snippet = snippetItems.first(where: { $0.id == id }) else { return }
        _ = await xpc.pasteText(text: snippet.body, plainText: plainText, saveAsNew: true)
    }

    private func nextRefreshSequence() -> UInt64 {
        refreshSequence += 1
        return refreshSequence
    }

    private func performRefresh(sequence: UInt64) async {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: String? = trimmed.isEmpty ? nil : trimmed
        let previousID: String? = items.indices.contains(focusedIndex) ? items[focusedIndex].id : nil

        let newItems: [DockItem]
        switch activeList {
        case .history:
            newItems = await loadFromXPC(query: query)
        case .pinned:
            newItems = await loadPinned(query: query)
        case let .pinboard(id):
            newItems = await loadPinboard(id: id, query: query)
        case .snippets:
            await loadSnippets()
            newItems = []
        }

        guard sequence == refreshSequence else { return }

        items = newItems
        if activeList == .snippets {
            focusedIndex = 0
            selection.removeAll()
            return
        }
        if let previousID, let newIndex = items.firstIndex(where: { $0.id == previousID }) {
            focusedIndex = newIndex
        } else {
            focusedIndex = 0
        }
        selection.removeAll()
    }

    private func loadFromXPC(query: String?) async -> [DockItem] {
        let fuzzyEnabled = isFuzzyEnabled()
        let effectiveQuery = fuzzyEnabled ? nil : query
        let limit = fuzzyEnabled ? 200 : 50

        let xpcItems: [ClipboardXPCMeta]
        if let clip {
            // Direct DB read — preferred path; works regardless of XPC state.
            xpcItems = await loadHistoryLocally(
                clip: clip, query: effectiveQuery, limit: limit
            )
        } else {
            let list = await xpc.listItems(
                query: effectiveQuery, pageToken: nil, limit: limit
            )
            xpcItems = list.items
        }

        let pinned = pinnedIDs()
        let candidates = xpcItems.map { meta in
            let isPinned: Bool
            if let id = RecordID(rawValue: meta.id) {
                isPinned = pinned.contains(id)
            } else {
                isPinned = false
            }
            return buildDockItem(from: meta, isPinned: isPinned)
        }
        return filteredAndRanked(items: candidates, query: query)
    }

    private func loadHistoryLocally(
        clip: ClipboardStore, query: String?, limit: Int
    ) async -> [ClipboardXPCMeta] {
        await Task.detached {
            let metas: [ClipboardItemMeta]
            if let query, !query.isEmpty {
                // Without an injected SearchStore, do an in-memory contains
                // filter over the most recent rows. Same fallback the menu-bar
                // popover uses, and tolerable up to a few hundred items.
                let recent = (try? clip.list(limit: max(limit, 200))) ?? []
                let lower = query.lowercased()
                metas = Array(recent.filter { $0.preview.lowercased().contains(lower) }.prefix(limit))
            } else {
                metas = (try? clip.list(limit: limit)) ?? []
            }
            return metas.map { Self.xpcMeta(from: $0, clip: clip) }
        }.value
    }

    private func loadPinned(query: String?) async -> [DockItem] {
        guard let pinned = try? PinnedPinboard.findOrCreate(in: pinboards) else { return [] }
        return await loadByIDs(pinned.itemIDs.map(\.rawValue), query: query, forcePinned: true)
    }

    private func loadPinboard(id: RecordID, query: String?) async -> [DockItem] {
        guard let board = (try? pinboards.list())?.first(where: { $0.id == id }) else { return [] }
        return await loadByIDs(board.itemIDs.map(\.rawValue), query: query, forcePinned: false)
    }

    private func loadByIDs(_ ids: [String], query: String?, forcePinned: Bool) async -> [DockItem] {
        guard !ids.isEmpty else { return [] }

        let xpcItems: [ClipboardXPCMeta]
        if let clip {
            xpcItems = await loadByIDsLocally(clip: clip, ids: ids)
        } else {
            xpcItems = await xpc.metasByIDs(ids: ids).items
        }

        let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
        var metas = xpcItems
        metas.sort { lhs, rhs in
            order[lhs.id, default: .max] < order[rhs.id, default: .max]
        }

        let pinned = pinnedIDs()
        let candidates = metas.map { meta in
            let isPinned: Bool
            if forcePinned {
                isPinned = true
            } else if let id = RecordID(rawValue: meta.id) {
                isPinned = pinned.contains(id)
            } else {
                isPinned = false
            }
            return buildDockItem(from: meta, isPinned: isPinned)
        }
        return filteredAndRanked(items: candidates, query: query)
    }

    private func loadByIDsLocally(clip: ClipboardStore, ids: [String]) async -> [ClipboardXPCMeta] {
        await Task.detached {
            let recordIDs = ids.compactMap(RecordID.init(rawValue:))
            let metas = (try? clip.metas(for: recordIDs)) ?? []
            return metas.map { Self.xpcMeta(from: $0, clip: clip) }
        }.value
    }

    /// Mirrors `ClipboardXPCService.xpcMeta(from:)` — keeps in-process and
    /// XPC-served reads producing identical DTOs. The body lookup is needed
    /// to attach blob info to image kinds; for non-image rows it is a no-op.
    nonisolated private static func xpcMeta(from meta: ClipboardItemMeta, clip: ClipboardStore) -> ClipboardXPCMeta {
        var imgWidth = 0
        var imgHeight = 0
        var imgBlobID: String?
        if let body = try? clip.body(for: meta.id),
           case let .image(blobID, w, h) = body
        {
            imgWidth = w
            imgHeight = h
            imgBlobID = blobID
        }
        return ClipboardXPCMeta(
            id: meta.id.rawValue,
            modified: meta.modified,
            kind: meta.kind.rawValue,
            preview: meta.preview,
            sourceAppBundleID: meta.sourceAppBundleID,
            imageWidth: imgWidth,
            imageHeight: imgHeight,
            imageBlobID: imgBlobID
        )
    }

    private func pinnedIDs() -> Set<RecordID> {
        guard let pinned = try? PinnedPinboard.findOrCreate(in: pinboards) else { return [] }
        return Set(pinned.itemIDs)
    }

    private func buildDockItem(from meta: ClipboardXPCMeta, isPinned: Bool) -> DockItem {
        let app: SourceApp? = meta.sourceAppBundleID.map {
            SourceApp(
                bundleID: $0,
                displayName: appIcons.displayName(for: $0),
                icon: appIcons.icon(for: $0)
            )
        }
        return DockItem(from: meta, sourceApp: app, isPinned: isPinned)
    }

    private func isFuzzyEnabled() -> Bool {
        AppGroupSettings.defaults.object(forKey: "search.fuzzy") as? Bool ?? false
    }

    private func filteredAndRanked(items: [DockItem], query: String?) -> [DockItem] {
        guard let query else { return items }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }

        if isFuzzyEnabled() {
            let rankedPreviews = FuzzyMatcher.rank(candidates: items.map(\.preview), query: trimmed)
            guard !rankedPreviews.isEmpty else { return [] }

            var orderByID: [String: Int] = [:]
            var rank = 0
            for preview in rankedPreviews {
                for item in items where item.preview == preview && orderByID[item.id] == nil {
                    orderByID[item.id] = rank
                    rank += 1
                    break
                }
            }
            return items
                .filter { orderByID[$0.id] != nil }
                .sorted { (orderByID[$0.id] ?? .max) < (orderByID[$1.id] ?? .max) }
        }

        let lower = trimmed.lowercased()
        return items.filter { $0.preview.lowercased().contains(lower) }
    }
}
