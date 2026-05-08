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

    var items: [DockItem] = []
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
        pinboards: PinboardStore
    ) {
        self.xpc = xpc
        self.appIcons = appIcons
        self.imageLoader = imageLoader
        self.fileLoader = fileLoader
        self.pinboards = pinboards
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
              var pinned = try? PinnedPinboard.findOrCreate(in: pinboards)
        else { return }

        if pinned.itemIDs.contains(recordID) {
            pinned.itemIDs.removeAll { $0 == recordID }
        } else {
            pinned.itemIDs.append(recordID)
        }
        pinned.modified = Date()
        try? pinboards.update(pinned)

        if activeList == .pinned || activeList == .history {
            await refresh()
        }
    }

    func addToPinboard(itemIDs: [String], boardID: RecordID) async {
        guard var pinboard = (try? pinboards.list())?.first(where: { $0.id == boardID }) else { return }

        for raw in itemIDs {
            guard let rid = RecordID(rawValue: raw), !pinboard.itemIDs.contains(rid) else { continue }
            pinboard.itemIDs.append(rid)
        }
        pinboard.modified = Date()
        try? pinboards.update(pinboard)
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
            newItems = []
        }

        guard sequence == refreshSequence else { return }

        items = newItems
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
        let list = await xpc.listItems(
            query: effectiveQuery,
            pageToken: nil,
            limit: fuzzyEnabled ? 200 : 50
        )
        let pinned = pinnedIDs()
        let candidates = list.items.map { meta in
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
        let list = await xpc.metasByIDs(ids: ids)

        let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
        var metas = list.items
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
