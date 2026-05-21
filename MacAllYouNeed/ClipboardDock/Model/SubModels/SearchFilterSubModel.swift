import AppKit
import Core
import Foundation
import Platform
import SwiftUI

/// Search + filter + refresh pipeline extracted from `ClipboardDockModel`. Owns
/// the refresh sequence counter, debounce task, query-based loading from XPC
/// or the local clip store, dedup of same-paste records, fuzzy/contains
/// ranking, and the `performRefresh` core that decides which slice loads.
///
/// Published state (`search`, `searchFocusRequestID`, `items`, `focusedIndex`,
/// `selection`, `activeList`) lives on the facade so SwiftUI observation
/// continues to fire from the same registrar. This sub-model holds only the
/// debounce task and the monotonic sequence number it uses to discard stale
/// responses.
@MainActor
final class SearchFilterSubModel {
    private unowned let model: ClipboardDockModel

    private var refreshDebounceTask: Task<Void, Never>?
    private var refreshSequence: UInt64 = 0

    init(model: ClipboardDockModel) {
        self.model = model
    }

    func requestSearchFocus() {
        model.searchFocusRequestID += 1
    }

    func refresh() async {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = nil
        let sequence = nextRefreshSequence()
        await performRefresh(sequence: sequence, preserveFocus: true)
    }

    func refreshForDockOpen(preserveFocus: Bool) async {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = nil
        let sequence = nextRefreshSequence()
        await performRefresh(sequence: sequence, preserveFocus: preserveFocus)
    }

    /// Animated variant — wraps the items-array assignment in the supplied
    /// animation so transitions on individual cards (vanish on delete, slide
    /// on insert) play instead of just popping.
    func refreshAnimated(_ animation: Animation?) async {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = nil
        let sequence = nextRefreshSequence()
        await performRefresh(sequence: sequence, preserveFocus: true, animation: animation)
    }

    func refreshDebounced() {
        refreshDebounceTask?.cancel()
        let sequence = nextRefreshSequence()
        refreshDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            await self?.performRefresh(sequence: sequence, preserveFocus: true)
        }
    }

    /// Cancels any pending debounced refresh and returns the next sequence
    /// number. Used by the facade's `switchList` so it can call
    /// `performRefresh` directly while clearing the previous list's items.
    func bumpRefreshSequence() -> UInt64 {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = nil
        return nextRefreshSequence()
    }

    private func nextRefreshSequence() -> UInt64 {
        refreshSequence += 1
        return refreshSequence
    }

    func performRefresh(
        sequence: UInt64,
        preserveFocus: Bool,
        animation: Animation? = nil
    ) async {
        let trimmed = model.search.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: String? = trimmed.isEmpty ? nil : trimmed
        let previousID: String? = preserveFocus && model.items.indices.contains(model.focusedIndex)
            ? model.items[model.focusedIndex].id
            : nil

        let newItems: [DockItem]
        switch model.activeList {
        case .history:
            newItems = await loadFromXPC(query: query)
        case let .pinboard(id):
            newItems = await loadPinboard(id: id, query: query)
        case .snippets:
            await model.snippetsSubModel.loadSnippets()
            newItems = []
        }

        guard sequence == refreshSequence else { return }

        let apply = {
            self.model.items = newItems
            if self.model.activeList == .snippets {
                self.model.focusedIndex = 0
                self.model.selection.removeAll()
                return
            }
            if let previousID, let newIndex = self.model.items.firstIndex(where: { $0.id == previousID }) {
                self.model.focusedIndex = newIndex
            } else {
                self.model.focusedIndex = 0
            }
            self.model.selection.removeAll()
        }
        if let animation {
            withAnimation(animation, apply)
        } else {
            apply()
        }
    }

    func loadFromXPC(query: String?) async -> [DockItem] {
        let fuzzyEnabled = isFuzzyEnabled()
        let effectiveQuery = fuzzyEnabled ? nil : query
        let limit = fuzzyEnabled ? 200 : 50

        let xpcItems: [ClipboardXPCMeta]
        if let clip = model.clip {
            xpcItems = await loadHistoryLocally(
                clip: clip, query: effectiveQuery, limit: limit
            )
        } else {
            let list = await model.xpc.listItems(
                query: effectiveQuery, pageToken: nil, limit: limit
            )
            xpcItems = list.items
        }

        let pinned = model.pinboardsSubModel.pinnedIDs()
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

    func loadHistoryLocally(
        clip: ClipboardStore, query: String?, limit: Int
    ) async -> [ClipboardXPCMeta] {
        await Task.detached {
            // Over-fetch so dedup has room to collapse multi-record pastes
            // (e.g. CleanShot writes png + file URL + sometimes rtf for one
            // copy action) before we trim to the requested limit.
            let fetchLimit = max(limit * 3, limit + 30)
            let raw: [ClipboardItemMeta]
            if let query, !query.isEmpty {
                let recent = (try? clip.list(limit: max(fetchLimit, 200))) ?? []
                let lower = query.lowercased()
                raw = Array(recent.filter { $0.preview.lowercased().contains(lower) })
            } else {
                raw = (try? clip.list(limit: fetchLimit)) ?? []
            }
            let deduped = SearchFilterSubModel.dedupSamePaste(raw, limit: limit)
            return deduped.map { SearchFilterSubModel.xpcMeta(from: $0, clip: clip) }
        }.value
    }

    /// Collapse multiple records produced by a single copy action into one.
    /// Apps like CleanShot write `image/png`, `public.file-url`, and
    /// sometimes other flavors in quick succession — daemon stores each as a
    /// separate row. Within a 0.5s window we keep the most informative one;
    /// file URLs win because they carry the filename + extension.
    nonisolated static func dedupSamePaste(
        _ sortedNewestFirst: [ClipboardItemMeta], limit: Int
    ) -> [ClipboardItemMeta] {
        var result: [ClipboardItemMeta] = []
        for item in sortedNewestFirst {
            if let last = result.last,
               abs(last.modified.timeIntervalSince(item.modified)) < 0.5
            {
                if pastePriority(item.preview) > pastePriority(last.preview) {
                    result[result.count - 1] = item
                }
                continue
            }
            result.append(item)
            if result.count >= limit { break }
        }
        return result
    }

    nonisolated static func pastePriority(_ preview: String) -> Int {
        if preview.hasPrefix("(") && preview.contains("file") { return 2 }
        if preview.hasPrefix("(image ") { return 1 }
        return 0
    }

    func loadPinboard(id: RecordID, query: String?) async -> [DockItem] {
        guard let board = (try? model.pinboardsSubModel.store.list())?.first(where: { $0.id == id }) else { return [] }
        return await loadByIDs(board.itemIDs.map(\.rawValue), query: query, forcePinned: false)
    }

    /// Load the implicit "Pinned" pinboard. Pre-existing in the monolithic
    /// model; retained as dead code for now (no call sites) per the surgical
    /// changes rule.
    func loadPinned(query: String?) async -> [DockItem] {
        guard let pinned = try? PinnedPinboard.findOrCreate(in: model.pinboardsSubModel.store) else { return [] }
        return await loadByIDs(pinned.itemIDs.map(\.rawValue), query: query, forcePinned: true)
    }

    func loadByIDs(_ ids: [String], query: String?, forcePinned: Bool) async -> [DockItem] {
        guard !ids.isEmpty else { return [] }

        let xpcItems: [ClipboardXPCMeta]
        if let clip = model.clip {
            xpcItems = await loadByIDsLocally(clip: clip, ids: ids)
        } else {
            xpcItems = await model.xpc.metasByIDs(ids: ids).items
        }

        let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
        var metas = xpcItems
        metas.sort { lhs, rhs in
            order[lhs.id, default: .max] < order[rhs.id, default: .max]
        }

        let pinned = model.pinboardsSubModel.pinnedIDs()
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

    func loadByIDsLocally(clip: ClipboardStore, ids: [String]) async -> [ClipboardXPCMeta] {
        await Task.detached {
            let recordIDs = ids.compactMap(RecordID.init(rawValue:))
            let metas = (try? clip.metas(for: recordIDs)) ?? []
            return metas.map { SearchFilterSubModel.xpcMeta(from: $0, clip: clip) }
        }.value
    }

    /// Mirrors `ClipboardXPCService.xpcMeta(from:)` — keeps in-process and
    /// XPC-served reads producing identical DTOs.
    nonisolated static func xpcMeta(from meta: ClipboardItemMeta, clip: ClipboardStore) -> ClipboardXPCMeta {
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
            imageBlobID: imgBlobID,
            customLabel: meta.customLabel
        )
    }

    func buildDockItem(from meta: ClipboardXPCMeta, isPinned: Bool) -> DockItem {
        let app: SourceApp? = meta.sourceAppBundleID.map {
            SourceApp(
                bundleID: $0,
                displayName: model.appIcons.displayName(for: $0),
                icon: model.appIcons.icon(for: $0)
            )
        }
        return DockItem(from: meta, sourceApp: app, isPinned: isPinned)
    }

    func isFuzzyEnabled() -> Bool {
        AppGroupSettings.defaults.object(forKey: "search.fuzzy") as? Bool ?? false
    }

    func filteredAndRanked(items: [DockItem], query: String?) -> [DockItem] {
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
