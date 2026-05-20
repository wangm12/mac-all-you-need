import AppKit
import Core
import Foundation
import Observation
import Platform
import SwiftUI

struct SnippetDraft: Identifiable, Equatable {
    let id: UUID
    let name: String
    let body: String
    let trigger: String?

    init(id: UUID = UUID(), name: String, body: String, trigger: String? = nil) {
        self.id = id
        self.name = name
        self.body = body
        self.trigger = trigger
    }
}

@MainActor
@Observable
final class ClipboardDockModel {
    let xpc: any ClipboardXPCInteracting
    let appIcons: AppIconResolver
    let imageLoader: ImageBlobLoader
    let fileLoader: FileURLLoader
    let fileThumbnailLoader: FileThumbnailLoader
    let pinboards: PinboardStore
    let snippets: SnippetStore
    /// Optional in-process read path. When non-nil, the History tab reads
    /// directly from the encrypted SQLite store the daemon writes to (same
    /// path the menu-bar popover uses) instead of going through XPC. This
    /// keeps the dock populated when the daemon's mach service registration
    /// fails — a known macOS Sequoia issue with SMAppService.loginItem.
    /// Writes (paste/delete/transform) still go through XPC.
    let clip: ClipboardStore?
    /// Companion to `clip`. Required for copy-to-pasteboard / delete /
    /// rename to work when XPC is unavailable.
    let blobs: BlobStore?

    var items: [DockItem] = []
    var snippetItems: [Snippet] = []
    var pendingSnippetDraft: SnippetDraft?
    var search: String = ""
    var searchFocusRequestID: Int = 0
    var focusedIndex: Int = 0
    var activeList: DockListSelector = .history
    var availableLists: [Pinboard] = []
    var selection: Set<DockItem.ID> = []
    var isQuickLooking: Bool = false
    var pendingTransform: TextTransform?
    var showTransformMenu: Bool = false
    var showCheatsheet: Bool = false
    var activeDraggedItemID: DockItem.ID?
    var isDockDragSurfaceActive: Bool = false
    /// Monotonic event used by child views with local drag state. A successful
    /// cross-view drop can finish without changing both global booleans, so
    /// views listen to this tick to clear local dim/hover state immediately.
    var dockDragCompletionCount: Int = 0
    /// Bundle ID of whichever app was frontmost just before the dock was
    /// shown. Captured by `DockWindowController.show()` so the right-click
    /// "Paste to <App>" menu item can name the right target — by the time
    /// the user clicks the menu, NSWorkspace's frontmost is the dock itself.
    var previousFrontmostBundleID: String?

    private var refreshDebounceTask: Task<Void, Never>?
    private var refreshSequence: UInt64 = 0

    init(
        xpc: any ClipboardXPCInteracting,
        appIcons: AppIconResolver,
        imageLoader: ImageBlobLoader,
        fileLoader: FileURLLoader,
        fileThumbnailLoader: FileThumbnailLoader,
        pinboards: PinboardStore,
        snippets: SnippetStore,
        clip: ClipboardStore? = nil,
        blobs: BlobStore? = nil
    ) {
        self.xpc = xpc
        self.appIcons = appIcons
        self.imageLoader = imageLoader
        self.fileLoader = fileLoader
        self.fileThumbnailLoader = fileThumbnailLoader
        self.pinboards = pinboards
        self.snippets = snippets
        self.clip = clip
        self.blobs = blobs
    }

    func loadAvailableLists() async {
        // Bootstrap the auto-created "Pinned" list so brand-new users have a
        // sensible default destination in the Pin-to-list menu. Idempotent.
        _ = try? PinnedPinboard.findOrCreate(in: pinboards)
        // No filter — Pinned is now treated as just another pinboard, ordered
        // alongside user-created lists by sort_order (insertion time).
        availableLists = (try? pinboards.list()) ?? []
    }

    func deletePinboard(id: RecordID) async {
        let board = (try? pinboards.list())?.first { $0.id == id }
        do {
            try pinboards.delete(id: id)
        } catch {
            return
        }

        if let board, PinnedPinboard.isDefaultPinned(board) {
            PinnedPinboard.markDeleted()
        }

        if activeList == .pinboard(id) {
            activeList = .history
            search = ""
            focusedIndex = 0
            selection.removeAll()
            selectionAnchorIndex = nil
            items = []
            await refresh()
        }

        await loadAvailableLists()
    }

    func switchList(_ selector: DockListSelector) async {
        activeList = selector
        search = ""
        focusedIndex = 0
        // Drop the previous list's items so performRefresh doesn't carry a
        // stale previousID across the tab switch — user expects the new tab
        // to land on its first (newest) card.
        items = []
        await performRefresh(sequence: nextRefreshSequence(), preserveFocus: false)
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

    func requestSearchFocus() {
        searchFocusRequestID += 1
    }

    /// Animated variant of `refresh` — wraps the items-array assignment in
    /// the supplied animation so transitions on individual cards (vanish on
    /// delete, slide on insert) play instead of just popping.
    func refreshAnimated(_ animation: Animation?) async {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = nil
        let sequence = nextRefreshSequence()
        await performRefresh(sequence: sequence, preserveFocus: true, animation: animation)
    }

    private var dockTabAnimation: Animation? {
        MAYNMotion.tabAnimation(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
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

    func finishDockDrag() {
        activeDraggedItemID = nil
        isDockDragSurfaceActive = false
        dockDragCompletionCount += 1
    }

    func togglePin(itemID: String) async {
        guard let recordID = RecordID(rawValue: itemID),
              let pinnedID = try? PinnedPinboard.findOrCreateForPinning(in: pinboards).id
        else { return }

        // Atomic read-modify-write so concurrent toggles do not lose updates.
        try? pinboards.mutate(id: pinnedID) { board in
            if board.itemIDs.contains(recordID) {
                board.itemIDs.removeAll { $0 == recordID }
            } else {
                board.itemIDs.append(recordID)
            }
        }

        if activeList == .history {
            await refresh()
        } else if case .pinboard = activeList {
            await refresh()
        }
    }

    /// True if `itemID` is currently in the implicit "📌 Pinned" pinboard.
    /// Used by the right-click menu to flip its label between Pin / Unpin.
    func isPinned(itemID: String) -> Bool {
        guard let rid = RecordID(rawValue: itemID),
              let pinned = try? PinnedPinboard.findOrCreate(in: pinboards)
        else { return false }
        return pinned.itemIDs.contains(rid)
    }

    /// True if the user can drag-reorder cards in the currently-active list.
    /// Only pinboards are durable ordered sources; History is recency-sorted,
    /// so letting users drag there creates a false "saved order" affordance.
    var isActiveListReorderable: Bool {
        if case .pinboard = activeList { return true }
        return false
    }

    /// IDs the always-visible action bar should operate on. Prefers the
    /// explicit multi-select; falls back to the focused (highlighted) card
    /// when nothing is selected so the bar is useful immediately after the
    /// dock opens — no need to click a card first.
    var effectiveActionTargets: [String] {
        if !selection.isEmpty {
            return items.map(\.id).filter { selection.contains($0) }
        }
        if items.indices.contains(focusedIndex) {
            return [items[focusedIndex].id]
        }
        return []
    }

    /// Show a brief floating "Copied / Pinned / Deleted" toast centered on
    /// the active screen. Routed through `CopyHUD` so the same chip is used
    /// regardless of whether the action came from the dock, the menu bar,
    /// or a context menu — and so it survives the dock dismissing.
    func triggerFeedback(_ message: String, symbol: String) {
        CopyHUD.show(message, symbol: symbol)
    }

    /// Copy a single card's content onto the system clipboard. Local path —
    /// no XPC required. The dock stays open; the user is expected to ⌘V into
    /// their target app themselves.
    func copyToClipboard(itemID: String) async {
        guard let rid = RecordID(rawValue: itemID),
              let clip,
              let blobs,
              let body = try? clip.body(for: rid)
        else { return }
        await MainActor.run {
            ClipboardXPCService.restoreToPasteboard(body: body, blobs: blobs, pasteboard: .general)
            // Mark this write so the daemon's PasteboardObserver skips it
            // — otherwise copying our own card right back into the
            // clipboard would re-capture as a brand-new history record on
            // the next poll, duplicating the same content forever.
            Self.markAsLocalWrite(.general)
        }
    }

    /// Copy every selected card's text onto the system clipboard, joined by
    /// newlines, in carousel order (newest first). Non-text bodies (images,
    /// files) are skipped — copy-many is only meaningful for text-like kinds.
    func copySelectionToClipboard() async {
        let ordered = items.map(\.id).filter { selection.contains($0) }
        guard !ordered.isEmpty, let clip else { return }
        let texts = ordered.compactMap { id -> String? in
            guard let rid = RecordID(rawValue: id),
                  let body = try? clip.body(for: rid)
            else { return nil }
            return Self.plainString(from: body)
        }
        guard !texts.isEmpty else { return }
        let joined = texts.joined(separator: "\n")
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(joined, forType: .string)
            Self.markAsLocalWrite(.general)
        }
    }

    /// Delete a single card. Local path removes the row and image blob, then
    /// refreshes once so the carousel can animate the removal.
    func deleteItem(itemID: String) async {
        await deleteItems(itemIDs: [itemID])
    }

    /// Delete multiple cards as one UI operation. This avoids the old N-item
    /// loop that posted N store notifications and ran N refresh animations,
    /// which made Cmd-A/Delete visibly remove cards one by one.
    func deleteItems(itemIDs: [String]) async {
        var seen = Set<String>()
        let ids = itemIDs.filter { seen.insert($0).inserted }
        guard !ids.isEmpty else { return }

        if clip != nil {
            var deletedCount = 0
            for id in ids where deleteLocalItem(itemID: id) {
                deletedCount += 1
            }
            guard deletedCount > 0 else { return }
            NotificationCenter.default.post(name: .clipboardStoreDidChange, object: nil)
        } else {
            for id in ids {
                _ = await xpc.deleteItem(id: id)
            }
        }

        await refreshAnimated(dockTabAnimation)
    }

    @discardableResult
    private func deleteLocalItem(itemID: String) -> Bool {
        guard let rid = RecordID(rawValue: itemID), let clip else { return false }
        if let blobs,
           let body = try? clip.body(for: rid),
           case let .image(blobID, _, _) = body
        {
            try? blobs.delete(id: blobID)
        }
        try? clip.delete(id: rid)
        return true
    }

    /// Apply or clear a user-set rename for a card. Empty string clears.
    func renameItem(itemID: String, label: String) async {
        guard let rid = RecordID(rawValue: itemID), let clip else { return }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        try? clip.setCustomLabel(id: rid, label: trimmed.isEmpty ? nil : trimmed)
        NotificationCenter.default.post(name: .clipboardStoreDidChange, object: nil)
        await refresh()
    }

    func addToPinboard(itemIDs: [String], boardID: RecordID) async {
        let recordIDs = itemIDs.compactMap(RecordID.init(rawValue:))
        guard !recordIDs.isEmpty else { return }
        try? pinboards.mutate(id: boardID) { board in
            for rid in recordIDs where !board.itemIDs.contains(rid) {
                board.itemIDs.append(rid)
            }
        }
        // If the user is currently looking at this pinboard, refresh so the
        // newly-added card shows up immediately.
        if case let .pinboard(active) = activeList, active == boardID {
            await refresh()
        }
        let boardName: String = {
            if let board = (try? pinboards.list())?.first(where: { $0.id == boardID }) {
                return board.name
            }
            return "list"
        }()
        let label = recordIDs.count > 1 ? "Pinned \(recordIDs.count) to \(boardName)" : "Pinned to \(boardName)"
        triggerFeedback(label, symbol: "pin.fill")
    }

    /// Move a card to a different position within the active pinboard and
    /// persist the new `itemIDs` order. History is recency-sorted and does not
    /// expose reorder targets.
    func reorderCardInActivePinboard(movingID: String, beforeID: String) async {
        await reorderCardInActivePinboard(
            movingID: movingID,
            targetID: beforeID,
            placement: .before
        )
    }

    /// Move a card before or after a target card within the active pinboard
    /// and persist the new `itemIDs` order. History is recency-sorted and does
    /// not expose reorder targets.
    func reorderCardInActivePinboard(
        movingID: String,
        targetID: String,
        placement: DockCardReorderPlacement
    ) async {
        guard movingID != targetID,
              let from = items.firstIndex(where: { $0.id == movingID }),
              items.contains(where: { $0.id == targetID })
        else { return }

        // Pinboard branch: durable reorder.
        if case let .pinboard(boardID) = activeList,
           let movingRID = RecordID(rawValue: movingID),
           let targetRID = RecordID(rawValue: targetID)
        {
            try? pinboards.mutate(id: boardID) { board in
                board.itemIDs.removeAll { $0 == movingRID }
                // Recompute the target's index AFTER removal — when the
                // dragged card was earlier in the array, removing shifted
                // every subsequent index down by 1, including the target's.
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
            var ids = items.map(\.id)
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
            if let animation = dockTabAnimation {
                withAnimation(animation) {
                    reorderCardsLocally(orderedIDs: ids)
                }
            } else {
                reorderCardsLocally(orderedIDs: ids)
            }
            return
        }

    }

    /// Move a card to the end of the active pinboard. Used by the trailing
    /// drop zone so the last slot is reachable; dropping on a card still means
    /// "insert before that card".
    func appendCardInActivePinboard(movingID: String) async {
        guard case let .pinboard(boardID) = activeList,
              let movingRID = RecordID(rawValue: movingID),
              items.contains(where: { $0.id == movingID })
        else { return }

        try? pinboards.mutate(id: boardID) { board in
            board.itemIDs.removeAll { $0 == movingRID }
            board.itemIDs.append(movingRID)
        }

        var ids = items.map(\.id)
        ids.removeAll { $0 == movingID }
        ids.append(movingID)
        if let animation = dockTabAnimation {
            withAnimation(animation) {
                reorderCardsLocally(orderedIDs: ids)
            }
        } else {
            reorderCardsLocally(orderedIDs: ids)
        }
    }

    /// Synchronous, in-memory reorder — mirrors `reorderPinboardsLocally`
    /// for cards. Drives the live shift animation as the user drags a card
    /// across its neighbors. `persistCardOrderInActivePinboard()` commits
    /// the final order on drop.
    func reorderCardsLocally(orderedIDs: [String]) {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        items = orderedIDs.compactMap { byID[$0] }
    }

    /// Write the in-memory `items` order back to the active pinboard.
    /// Call after a live drag has settled so the order survives a relaunch.
    func persistCardOrderInActivePinboard() async {
        guard case let .pinboard(boardID) = activeList else { return }
        let orderedRIDs = items.compactMap { RecordID(rawValue: $0.id) }
        try? pinboards.mutate(id: boardID) { board in
            // Preserve any IDs that aren't currently in `items` (e.g. items
            // hidden by a search filter) by appending them after the
            // explicit order.
            let visibleSet = Set(orderedRIDs)
            let leftovers = board.itemIDs.filter { !visibleSet.contains($0) }
            board.itemIDs = orderedRIDs + leftovers
        }
    }

    /// Reorder user-created pinboards. `orderedIDs` is the new full ordering of
    /// `availableLists`; the store persists `sort_order` atomically. Reloads
    /// `availableLists` so the tab bar reflects the change immediately.
    func reorderPinboards(orderedIDs: [RecordID]) async {
        try? pinboards.reorder(orderedIDs: orderedIDs)
        await loadAvailableLists()
    }

    /// Synchronous, in-memory reorder used during a live drag. Mutating
    /// `availableLists` immediately lets the tab bar slide as the dragged tab
    /// crosses each neighbor, without paying for a disk write per hover event.
    /// Pair with `persistPinboardOrder()` on drop to commit the final order.
    func reorderPinboardsLocally(orderedIDs: [RecordID]) {
        let byID = Dictionary(uniqueKeysWithValues: availableLists.map { ($0.id, $0) })
        availableLists = orderedIDs.compactMap { byID[$0] }
    }

    /// Persist whatever the current `availableLists` ordering is. Call after a
    /// live drag has settled so the in-memory order survives a relaunch.
    func persistPinboardOrder() async {
        try? pinboards.reorder(orderedIDs: availableLists.map(\.id))
        await loadAvailableLists()
    }

    func focusForward() {
        guard !items.isEmpty else { return }
        let next = min(items.count - 1, focusedIndex + 1)
        // Replace selection with the newly-focused card so the highlight
        // border follows arrow keys (Finder-style). Without this, focus
        // and selection diverge after a click — the dock card stops
        // showing the accent border even though arrows moved focus.
        selectOnly(itemID: items[next].id)
    }

    func focusBackward() {
        guard !items.isEmpty else { return }
        let prev = max(0, focusedIndex - 1)
        selectOnly(itemID: items[prev].id)
    }

    func toggleSelection(itemID: String) {
        if selection.contains(itemID) {
            selection.remove(itemID)
        } else {
            selection.insert(itemID)
        }
    }

    /// Anchor index for shift-click range selection. Set whenever the user
    /// performs a "fresh" single-click (replace-selection) or a Cmd-click
    /// (multi-select toggle). Shift-click extends from this anchor to the
    /// shift-clicked target, mirroring Finder's behavior.
    var selectionAnchorIndex: Int?

    /// Replace the entire selection with this single card and move focus to
    /// it. Standard macOS single-click semantics — a bare click does NOT
    /// extend an existing multi-select. Use `toggleSelection` from ⌘+click
    /// to actually multi-select.
    func selectOnly(itemID: String) {
        selection = [itemID]
        if let idx = items.firstIndex(where: { $0.id == itemID }) {
            focusedIndex = idx
            selectionAnchorIndex = idx
        }
    }

    /// ⌘-click semantics: toggle the card in/out of the selection AND move
    /// the anchor (and focus) to it, mirroring Finder. A subsequent
    /// ⇧-click extends from this card.
    func cmdToggleSelection(itemID: String) {
        toggleSelection(itemID: itemID)
        if let idx = items.firstIndex(where: { $0.id == itemID }) {
            focusedIndex = idx
            selectionAnchorIndex = idx
        }
    }

    /// ⇧-click semantics: extend selection from the current anchor to the
    /// clicked card, inclusive. Existing selection outside the range is
    /// preserved (Finder adds to it). Anchor stays where it was.
    func shiftExtendSelection(toItemID itemID: String) {
        guard let target = items.firstIndex(where: { $0.id == itemID }) else { return }
        let anchor = selectionAnchorIndex ?? focusedIndex
        let lower = min(anchor, target)
        let upper = max(anchor, target)
        for rangeIndex in lower ... upper where items.indices.contains(rangeIndex) {
            selection.insert(items[rangeIndex].id)
        }
        focusedIndex = target
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

    /// Paste whatever the always-visible action bar should target — the
    /// multi-selection if present, otherwise the focused card alone.
    func pasteEffectiveTargets(plainText: Bool) async {
        let ids = effectiveActionTargets
        guard !ids.isEmpty else { return }
        if ids.count == 1 {
            _ = await xpc.paste(itemID: ids[0], plainText: plainText)
        } else {
            _ = await xpc.pasteMany(itemIDs: ids, delimiter: "\n", plainText: plainText)
        }
    }

    /// Copy the effective targets to the system clipboard. Dock stays open;
    /// the user pastes manually with ⌘V into their target app. For multi-
    /// select, all text-like bodies are concatenated with newlines.
    func copyEffectiveTargets(plainText: Bool) async {
        let ids = effectiveActionTargets
        guard !ids.isEmpty, let clip else { return }

        if ids.count == 1, !plainText {
            // Rich-fidelity single-card copy reuses the daemon's pasteboard
            // restore (handles RTF, HTML, image, file URLs).
            await copyToClipboard(itemID: ids[0])
            triggerFeedback("Copied", symbol: "checkmark.circle.fill")
            return
        }

        // Plain-text path: extract a string from each body. Multi-select
        // also collapses to plain so we can join cards.
        let strings: [String] = ids.compactMap { id -> String? in
            guard let rid = RecordID(rawValue: id),
                  let body = try? clip.body(for: rid)
            else { return nil }
            return Self.plainString(from: body)
        }
        guard !strings.isEmpty else { return }
        let joined = strings.joined(separator: "\n")
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(joined, forType: .string)
            Self.markAsLocalWrite(.general)
        }
        let label = ids.count > 1 ? "Copied \(ids.count) items" : "Copied"
        triggerFeedback(label, symbol: "checkmark.circle.fill")
    }

    /// Tag a pasteboard write so the daemon's `PasteboardObserver.tick()`
    /// recognises it as our own and skips re-capturing the content as a
    /// new history record. The sentinel UTI is the same one
    /// `ClipboardXPCService.markAsDaemonWrite()` uses.
    private static func markAsLocalWrite(_ pasteboard: NSPasteboard) {
        pasteboard.setData(Data([0]), forType: PasteboardUTI.daemonWrite)
    }

    /// Strip a clipboard body to a plain string. Returns nil for kinds that
    /// have no meaningful text representation (images).
    private static func plainString(from body: ClipboardRecord) -> String? {
        switch body {
        case let .text(s): return s
        case let .html(s):
            if let data = s.data(using: .utf8),
               let attributed = NSAttributedString(html: data, documentAttributes: nil) {
                return attributed.string.trimmingCharacters(in: .newlines)
            }
            return s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        case let .rtf(data): return NSAttributedString(rtf: data, documentAttributes: nil)?.string
        case .image: return nil
        case let .files(urls): return urls.map(\.path).joined(separator: "\n")
        }
    }

    /// Delete the bar's effective targets (multi-select or focused card).
    func deleteEffectiveTargets() async {
        let ids = effectiveActionTargets
        guard !ids.isEmpty else { return }
        await deleteItems(itemIDs: ids)
        let label = ids.count > 1 ? "Deleted \(ids.count) items" : "Deleted"
        triggerFeedback(label, symbol: "trash.fill")
    }

    func deleteSelected() async {
        let ids = Array(selection)
        await deleteItems(itemIDs: ids)
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

    func copySnippet(id: RecordID) {
        guard let snippet = snippetItems.first(where: { $0.id == id }) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snippet.body, forType: .string)
        Self.markAsLocalWrite(.general)
    }

    @discardableResult
    func beginSnippetDraftFromClipboard(itemIDs: [String]) async -> Bool {
        var seen = Set<String>()
        var bodies: [String] = []
        for itemID in itemIDs {
            guard seen.insert(itemID).inserted else { continue }
            if let body = await snippetBody(forClipboardItemID: itemID) {
                bodies.append(body)
            }
        }
        guard !bodies.isEmpty else {
            triggerFeedback("Snippet needs text", symbol: "exclamationmark.triangle.fill")
            return false
        }

        pendingSnippetDraft = SnippetDraft(
            name: "Clipboard snippet",
            body: bodies.joined(separator: "\n")
        )
        return true
    }

    func clearPendingSnippetDraft() {
        pendingSnippetDraft = nil
    }

    private func nextRefreshSequence() -> UInt64 {
        refreshSequence += 1
        return refreshSequence
    }

    private func snippetBody(forClipboardItemID itemID: String) async -> String? {
        if let rid = RecordID(rawValue: itemID),
           let clip,
           let record = try? clip.body(for: rid),
           let body = Self.plainString(from: record),
           !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return body
        }

        guard let body = await xpc.bodyText(forID: itemID),
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return body
    }

    private func performRefresh(
        sequence: UInt64,
        preserveFocus: Bool,
        animation: Animation? = nil
    ) async {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: String? = trimmed.isEmpty ? nil : trimmed
        let previousID: String? = preserveFocus && items.indices.contains(focusedIndex)
            ? items[focusedIndex].id
            : nil

        let newItems: [DockItem]
        switch activeList {
        case .history:
            newItems = await loadFromXPC(query: query)
        case let .pinboard(id):
            newItems = await loadPinboard(id: id, query: query)
        case .snippets:
            await loadSnippets()
            newItems = []
        }

        guard sequence == refreshSequence else { return }

        // Apply state changes inside withAnimation when caller asked for it,
        // so per-card transitions on the carousel actually play (delete
        // vanish, insert slide).
        let apply = {
            self.items = newItems
            if self.activeList == .snippets {
                self.focusedIndex = 0
                self.selection.removeAll()
                return
            }
            if let previousID, let newIndex = self.items.firstIndex(where: { $0.id == previousID }) {
                self.focusedIndex = newIndex
            } else {
                self.focusedIndex = 0
            }
            self.selection.removeAll()
        }
        if let animation {
            withAnimation(animation, apply)
        } else {
            apply()
        }
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
            let deduped = Self.dedupSamePaste(raw, limit: limit)
            return deduped.map { Self.xpcMeta(from: $0, clip: clip) }
        }.value
    }

    /// Collapse multiple records produced by a single copy action into one.
    /// Apps like CleanShot write `image/png`, `public.file-url`, and
    /// sometimes other flavors in quick succession — daemon stores each as a
    /// separate row. Within a 0.5s window we keep the most informative one;
    /// file URLs win because they carry the filename + extension. List is
    /// sorted by `modified DESC`, so we walk from newest to oldest.
    nonisolated private static func dedupSamePaste(
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

    /// Higher = preferred when collapsing duplicates. file > image > everything
    /// else; reasoning: a file URL is enough to reconstruct the image AND tells
    /// the user where it came from, so it's strictly more informative.
    nonisolated private static func pastePriority(_ preview: String) -> Int {
        if preview.hasPrefix("(") && preview.contains("file") { return 2 }
        if preview.hasPrefix("(image ") { return 1 }
        return 0
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
            imageBlobID: imgBlobID,
            customLabel: meta.customLabel
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
