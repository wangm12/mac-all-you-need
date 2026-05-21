import AppKit
import Core
import Foundation
import Platform
import SwiftUI

/// Pinboards slice extracted from `ClipboardDockModel`. Owns CRUD against the
/// `PinboardStore`, pinning, list ordering, card ordering within pinboards,
/// and load-by-IDs paths used when the active list is a pinboard or the
/// implicit "Pinned" list.
///
/// All published state (`availableLists`, `items`, `activeList`, `focusedIndex`,
/// `selection`, `search`) is held on the facade `ClipboardDockModel` so SwiftUI
/// observation behavior is preserved exactly. This sub-model mutates the
/// facade's state through an `unowned` back reference.
@MainActor
final class PinboardsSubModel {
    private unowned let model: ClipboardDockModel
    let store: PinboardStore

    init(model: ClipboardDockModel, store: PinboardStore) {
        self.model = model
        self.store = store
    }

    func loadAvailableLists() async {
        // Bootstrap the auto-created "Pinned" list so brand-new users have a
        // sensible default destination in the Pin-to-list menu. Idempotent.
        _ = try? PinnedPinboard.findOrCreate(in: store)
        // No filter — Pinned is now treated as just another pinboard, ordered
        // alongside user-created lists by sort_order (insertion time).
        model.availableLists = (try? store.list()) ?? []
    }

    func deletePinboard(id: RecordID) async {
        let board = (try? store.list())?.first { $0.id == id }
        do {
            try store.delete(id: id)
        } catch {
            return
        }

        if let board, PinnedPinboard.isDefaultPinned(board) {
            PinnedPinboard.markDeleted()
        }

        if model.activeList == .pinboard(id) {
            model.activeList = .history
            model.search = ""
            model.focusedIndex = 0
            model.selection.removeAll()
            model.selectionAnchorIndex = nil
            model.items = []
            await model.refresh()
        }

        await loadAvailableLists()
    }

    func togglePin(itemID: String) async {
        guard let recordID = RecordID(rawValue: itemID),
              let pinnedID = try? PinnedPinboard.findOrCreateForPinning(in: store).id
        else { return }

        // Atomic read-modify-write so concurrent toggles do not lose updates.
        try? store.mutate(id: pinnedID) { board in
            if board.itemIDs.contains(recordID) {
                board.itemIDs.removeAll { $0 == recordID }
            } else {
                board.itemIDs.append(recordID)
            }
        }

        if model.activeList == .history {
            await model.refresh()
        } else if case .pinboard = model.activeList {
            await model.refresh()
        }
    }

    /// True if `itemID` is currently in the implicit "📌 Pinned" pinboard.
    func isPinned(itemID: String) -> Bool {
        guard let rid = RecordID(rawValue: itemID),
              let pinned = try? PinnedPinboard.findOrCreate(in: store)
        else { return false }
        return pinned.itemIDs.contains(rid)
    }

    func addToPinboard(itemIDs: [String], boardID: RecordID) async {
        let recordIDs = itemIDs.compactMap(RecordID.init(rawValue:))
        guard !recordIDs.isEmpty else { return }
        try? store.mutate(id: boardID) { board in
            for rid in recordIDs where !board.itemIDs.contains(rid) {
                board.itemIDs.append(rid)
            }
        }
        if case let .pinboard(active) = model.activeList, active == boardID {
            await model.refresh()
        }
        let boardName: String = {
            if let board = (try? store.list())?.first(where: { $0.id == boardID }) {
                return board.name
            }
            return "list"
        }()
        let label = recordIDs.count > 1 ? "Pinned \(recordIDs.count) to \(boardName)" : "Pinned to \(boardName)"
        model.triggerFeedback(label, symbol: "pin.fill")
    }

    func reorderCardInActivePinboard(
        movingID: String,
        targetID: String,
        placement: DockCardReorderPlacement
    ) async {
        guard movingID != targetID,
              let from = model.items.firstIndex(where: { $0.id == movingID }),
              model.items.contains(where: { $0.id == targetID })
        else { return }

        if case let .pinboard(boardID) = model.activeList,
           let movingRID = RecordID(rawValue: movingID),
           let targetRID = RecordID(rawValue: targetID)
        {
            try? store.mutate(id: boardID) { board in
                board.itemIDs.removeAll { $0 == movingRID }
                if let targetIdx = board.itemIDs.firstIndex(of: targetRID) {
                    let insertIndex: Int
                    switch placement {
                    case .before:
                        insertIndex = targetIdx
                    case .after:
                        insertIndex = min(targetIdx + 1, board.itemIDs.count)
                    }
                    board.itemIDs.insert(movingRID, at: insertIndex)
                } else {
                    board.itemIDs.append(movingRID)
                }
            }
            var ids = model.items.map(\.id)
            ids.remove(at: from)
            let targetIndex = ids.firstIndex(of: targetID) ?? ids.count
            let insertIndex: Int
            switch placement {
            case .before:
                insertIndex = targetIndex
            case .after:
                insertIndex = min(targetIndex + 1, ids.count)
            }
            ids.insert(movingID, at: insertIndex)
            if let animation = model.dockTabAnimationForSubModels {
                withAnimation(animation) {
                    reorderCardsLocally(orderedIDs: ids)
                }
            } else {
                reorderCardsLocally(orderedIDs: ids)
            }
            return
        }
    }

    func appendCardInActivePinboard(movingID: String) async {
        guard case let .pinboard(boardID) = model.activeList,
              let movingRID = RecordID(rawValue: movingID),
              model.items.contains(where: { $0.id == movingID })
        else { return }

        try? store.mutate(id: boardID) { board in
            board.itemIDs.removeAll { $0 == movingRID }
            board.itemIDs.append(movingRID)
        }

        var ids = model.items.map(\.id)
        ids.removeAll { $0 == movingID }
        ids.append(movingID)
        if let animation = model.dockTabAnimationForSubModels {
            withAnimation(animation) {
                reorderCardsLocally(orderedIDs: ids)
            }
        } else {
            reorderCardsLocally(orderedIDs: ids)
        }
    }

    func reorderCardsLocally(orderedIDs: [String]) {
        let byID = Dictionary(uniqueKeysWithValues: model.items.map { ($0.id, $0) })
        model.items = orderedIDs.compactMap { byID[$0] }
    }

    func persistCardOrderInActivePinboard() async {
        guard case let .pinboard(boardID) = model.activeList else { return }
        let orderedRIDs = model.items.compactMap { RecordID(rawValue: $0.id) }
        try? store.mutate(id: boardID) { board in
            let visibleSet = Set(orderedRIDs)
            let leftovers = board.itemIDs.filter { !visibleSet.contains($0) }
            board.itemIDs = orderedRIDs + leftovers
        }
    }

    func reorderPinboards(orderedIDs: [RecordID]) async {
        try? store.reorder(orderedIDs: orderedIDs)
        await loadAvailableLists()
    }

    func reorderPinboardsLocally(orderedIDs: [RecordID]) {
        let byID = Dictionary(uniqueKeysWithValues: model.availableLists.map { ($0.id, $0) })
        model.availableLists = orderedIDs.compactMap { byID[$0] }
    }

    func persistPinboardOrder() async {
        try? store.reorder(orderedIDs: model.availableLists.map(\.id))
        await loadAvailableLists()
    }

    /// IDs currently in the implicit "Pinned" pinboard — used by the refresh
    /// pipeline to flag cards as pinned regardless of which list they are
    /// being rendered through.
    func pinnedIDs() -> Set<RecordID> {
        guard let pinned = try? PinnedPinboard.findOrCreate(in: store) else { return [] }
        return Set(pinned.itemIDs)
    }
}
