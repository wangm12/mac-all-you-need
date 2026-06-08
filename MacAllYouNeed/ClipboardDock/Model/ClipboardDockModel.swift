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

/// Facade over the dock data model. Owns all `@Observable` published state so
/// SwiftUI binding (`$model.search`, `$model.showTransformMenu`) and direct
/// reads/writes (`model.items`, `model.selection`, ...) continue to flow
/// through the same observation registrar.
///
/// Behavior is delegated to five sub-models:
/// - `SnippetsSubModel`        — snippet CRUD, paste/copy, draft creation.
/// - `PinboardsSubModel`       — pinboard CRUD, pin/unpin, card and list reorder.
/// - `SearchFilterSubModel`    — refresh pipeline, query/debounce, dedup, ranking.
/// - `TransformsSubModel`      — text-transform dispatch on focused / selected cards.
/// - `DragDropSubModel`        — drag teardown (clear active drag, bump completion tick).
///
/// Each sub-model holds an `unowned` back reference to this facade and mutates
/// the facade's stored state directly. This keeps the observation surface
/// byte-identical to the pre-decomposition monolith — verified by
/// `ClipboardDockModelSpineSnapshotTests`.
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
    /// FTS index for in-process history search (same DB the daemon indexes).
    let searchStore: SearchStore?
    /// Background history search (FTS, dedup, fuzzy/smart rank).
    let clipboardWorker: ClipboardWorker?

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

    /// Anchor index for shift-click range selection. Set whenever the user
    /// performs a "fresh" single-click (replace-selection) or a Cmd-click
    /// (multi-select toggle). Shift-click extends from this anchor to the
    /// shift-clicked target, mirroring Finder's behavior.
    var selectionAnchorIndex: Int?

    // MARK: - Sub-models
    //
    // Initialized to placeholder instances and bound in `init` so each sub-model
    // can capture `unowned self` after the facade's stored properties are set.
    // The sub-models are excluded from observation tracking — they hold only
    // back references and (in the case of SearchFilterSubModel) a debounce
    // task; their own identity never changes during the facade's lifetime.

    @ObservationIgnored var snippetsSubModel: SnippetsSubModel!
    @ObservationIgnored var pinboardsSubModel: PinboardsSubModel!
    @ObservationIgnored var searchFilterSubModel: SearchFilterSubModel!
    @ObservationIgnored var transformsSubModel: TransformsSubModel!
    @ObservationIgnored var dragDropSubModel: DragDropSubModel!

    init(
        xpc: any ClipboardXPCInteracting,
        appIcons: AppIconResolver,
        imageLoader: ImageBlobLoader,
        fileLoader: FileURLLoader,
        fileThumbnailLoader: FileThumbnailLoader,
        pinboards: PinboardStore,
        snippets: SnippetStore,
        clip: ClipboardStore? = nil,
        blobs: BlobStore? = nil,
        searchStore: SearchStore? = nil,
        clipboardWorker: ClipboardWorker? = nil
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
        self.searchStore = searchStore
        self.clipboardWorker = clipboardWorker

        snippetsSubModel = SnippetsSubModel(model: self, store: snippets)
        pinboardsSubModel = PinboardsSubModel(model: self, store: pinboards)
        searchFilterSubModel = SearchFilterSubModel(model: self)
        transformsSubModel = TransformsSubModel(model: self)
        dragDropSubModel = DragDropSubModel(model: self)
    }

    // MARK: - Pinboard delegation

    func loadAvailableLists() async {
        await pinboardsSubModel.loadAvailableLists()
    }

    func deletePinboard(id: RecordID) async {
        await pinboardsSubModel.deletePinboard(id: id)
    }

    func togglePin(itemID: String) async {
        await pinboardsSubModel.togglePin(itemID: itemID)
    }

    func isPinned(itemID: String) -> Bool {
        pinboardsSubModel.isPinned(itemID: itemID)
    }

    func addToPinboard(itemIDs: [String], boardID: RecordID) async {
        await pinboardsSubModel.addToPinboard(itemIDs: itemIDs, boardID: boardID)
    }

    /// Move a card to a different position within the active pinboard.
    func reorderCardInActivePinboard(movingID: String, beforeID: String) async {
        await reorderCardInActivePinboard(
            movingID: movingID,
            targetID: beforeID,
            placement: .before
        )
    }

    func reorderCardInActivePinboard(
        movingID: String,
        targetID: String,
        placement: DockCardReorderPlacement
    ) async {
        await pinboardsSubModel.reorderCardInActivePinboard(
            movingID: movingID, targetID: targetID, placement: placement
        )
    }

    func appendCardInActivePinboard(movingID: String) async {
        await pinboardsSubModel.appendCardInActivePinboard(movingID: movingID)
    }

    func reorderCardsLocally(orderedIDs: [String]) {
        pinboardsSubModel.reorderCardsLocally(orderedIDs: orderedIDs)
    }

    func persistCardOrderInActivePinboard() async {
        await pinboardsSubModel.persistCardOrderInActivePinboard()
    }

    func reorderPinboards(orderedIDs: [RecordID]) async {
        await pinboardsSubModel.reorderPinboards(orderedIDs: orderedIDs)
    }

    func reorderPinboardsLocally(orderedIDs: [RecordID]) {
        pinboardsSubModel.reorderPinboardsLocally(orderedIDs: orderedIDs)
    }

    func persistPinboardOrder() async {
        await pinboardsSubModel.persistPinboardOrder()
    }

    // MARK: - Refresh / search delegation

    func switchList(_ selector: DockListSelector) async {
        activeList = selector
        search = ""
        focusedIndex = 0
        // Drop the previous list's items so performRefresh doesn't carry a
        // stale previousID across the tab switch — user expects the new tab
        // to land on its first (newest) card.
        items = []
        await searchFilterSubModel.performRefresh(
            sequence: searchFilterSubModel.bumpRefreshSequence(),
            preserveFocus: false
        )
    }

    func refresh() async {
        await searchFilterSubModel.refresh()
    }

    func refreshForDockOpen(preserveFocus: Bool) async {
        await searchFilterSubModel.refreshForDockOpen(preserveFocus: preserveFocus)
    }

    func requestSearchFocus() {
        searchFilterSubModel.requestSearchFocus()
    }

    /// Clears the query when the dock is dismissed so the next open starts fresh.
    func prepareForDismiss() {
        search = ""
        searchFilterSubModel.bumpRefreshSequence()
    }

    /// Animated variant of `refresh`.
    func refreshAnimated(_ animation: Animation?) async {
        await searchFilterSubModel.refreshAnimated(animation)
    }

    func refreshDebounced() {
        searchFilterSubModel.refreshDebounced()
    }

    /// Animation used by reorder paths that need to play the tab/card animation
    /// when applying their changes. Exposed to sub-models via this accessor.
    var dockTabAnimationForSubModels: Animation? {
        MAYNMotion.tabAnimation(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    // MARK: - Drag

    func finishDockDrag() {
        dragDropSubModel.finishDockDrag()
    }

    // MARK: - Action targets (cross-cutting helpers)

    /// True if the user can drag-reorder cards in the currently-active list.
    /// Only pinboards are durable ordered sources; History is recency-sorted,
    /// so letting users drag there creates a false "saved order" affordance.
    var isActiveListReorderable: Bool {
        if case .pinboard = activeList { return true }
        return false
    }

    /// IDs the always-visible action bar should operate on. Prefers the
    /// explicit multi-select; falls back to the focused (highlighted) card
    /// when nothing is selected.
    var effectiveActionTargets: [String] {
        if !selection.isEmpty {
            return items.map(\.id).filter { selection.contains($0) }
        }
        if items.indices.contains(focusedIndex) {
            return [items[focusedIndex].id]
        }
        return []
    }

    /// Show a brief floating "Copied / Pinned / Deleted" toast.
    func triggerFeedback(_ message: String, symbol: String) {
        CopyHUD.show(message, symbol: symbol)
    }

    // MARK: - Clipboard copy / paste / delete / rename

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

    /// Delete a single card.
    func deleteItem(itemID: String) async {
        await deleteItems(itemIDs: [itemID])
    }

    /// Delete multiple cards as one UI operation.
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

        await refreshAnimated(dockTabAnimationForSubModels)
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

    /// Apply or clear a user-set rename for a card.
    func renameItem(itemID: String, label: String) async {
        guard let rid = RecordID(rawValue: itemID), let clip else { return }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        try? clip.setCustomLabel(id: rid, label: trimmed.isEmpty ? nil : trimmed)
        NotificationCenter.default.post(name: .clipboardStoreDidChange, object: nil)
        await refresh()
    }

    // MARK: - Focus + selection (cross-cutting; touches items + snippetItems)

    func focusForward() {
        if activeList == .snippets {
            guard !snippetItems.isEmpty else { return }
            focusedIndex = min(snippetItems.count - 1, focusedIndex + 1)
            selection.removeAll()
            return
        }
        guard !items.isEmpty else { return }
        let next = min(items.count - 1, focusedIndex + 1)
        // Replace selection with the newly-focused card so the highlight
        // border follows arrow keys (Finder-style). Without this, focus
        // and selection diverge after a click — the dock card stops
        // showing the accent border even though arrows moved focus.
        selectOnly(itemID: items[next].id)
    }

    func focusBackward() {
        if activeList == .snippets {
            guard !snippetItems.isEmpty else { return }
            focusedIndex = max(0, focusedIndex - 1)
            selection.removeAll()
            return
        }
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

    /// Replace the entire selection with this single card and move focus to
    /// it. Standard macOS single-click semantics.
    func selectOnly(itemID: String) {
        selection = [itemID]
        if let idx = items.firstIndex(where: { $0.id == itemID }) {
            focusedIndex = idx
            selectionAnchorIndex = idx
        }
    }

    /// ⌘-click semantics: toggle in/out, move anchor + focus to the card.
    func cmdToggleSelection(itemID: String) {
        toggleSelection(itemID: itemID)
        if let idx = items.firstIndex(where: { $0.id == itemID }) {
            focusedIndex = idx
            selectionAnchorIndex = idx
        }
    }

    /// ⇧-click semantics: extend from anchor to target, inclusive.
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

    // MARK: - Paste / copy / delete on effective targets

    func pasteSelectionInOrder(delimiter: String, plainText: Bool) async {
        let orderedIDs = items.map(\.id).filter { selection.contains($0) }
        guard !orderedIDs.isEmpty else { return }
        _ = await xpc.pasteMany(itemIDs: orderedIDs, delimiter: delimiter, plainText: plainText)
    }

    func pasteEffectiveTargets(plainText: Bool) async {
        let ids = effectiveActionTargets
        guard !ids.isEmpty else { return }
        if ids.count == 1 {
            _ = await xpc.paste(itemID: ids[0], plainText: plainText)
        } else {
            _ = await xpc.pasteMany(itemIDs: ids, delimiter: "\n", plainText: plainText)
        }
    }

    func copyEffectiveTargets(plainText: Bool) async {
        let ids = effectiveActionTargets
        guard !ids.isEmpty, let clip else { return }

        if ids.count == 1, !plainText {
            await copyToClipboard(itemID: ids[0])
            triggerFeedback("Copied", symbol: "checkmark.circle.fill")
            return
        }

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

    // MARK: - Transforms

    func applyTransform(_ transform: TextTransform, saveAsNew: Bool) async {
        await transformsSubModel.applyTransform(transform, saveAsNew: saveAsNew)
    }

    // MARK: - Snippets delegation

    func loadSnippets() async {
        await snippetsSubModel.loadSnippets()
    }

    func createSnippet(name: String, body: String, trigger: String?) async throws {
        try await snippetsSubModel.createSnippet(name: name, body: body, trigger: trigger)
    }

    func updateSnippet(id: RecordID, name: String, body: String, trigger: String?) async throws {
        try await snippetsSubModel.updateSnippet(id: id, name: name, body: body, trigger: trigger)
    }

    func deleteSnippet(id: RecordID) async {
        await snippetsSubModel.deleteSnippet(id: id)
    }

    func duplicateSnippet(id: RecordID) async {
        await snippetsSubModel.duplicateSnippet(id: id)
    }

    func pasteSnippet(id: RecordID, plainText: Bool) async {
        await snippetsSubModel.pasteSnippet(id: id, plainText: plainText)
    }

    func pasteFocusedSnippet(plainText: Bool) async {
        await snippetsSubModel.pasteFocusedSnippet(plainText: plainText)
    }

    func copySnippet(id: RecordID) {
        snippetsSubModel.copySnippet(id: id)
    }

    func copyFocusedSnippet() {
        snippetsSubModel.copyFocusedSnippet()
    }

    @discardableResult
    func beginSnippetDraftFromClipboard(itemIDs: [String]) async -> Bool {
        await snippetsSubModel.beginSnippetDraftFromClipboard(itemIDs: itemIDs)
    }

    func clearPendingSnippetDraft() {
        snippetsSubModel.clearPendingSnippetDraft()
    }

    // MARK: - Pasteboard tagging + plain-text extraction
    //
    // Kept on the facade so the existing `Self.markAsLocalWrite` /
    // `Self.plainString` call sites inside facade methods compile unchanged.
    // Sub-models reach these helpers through the `*ForSubModels` aliases.

    /// Tag a pasteboard write so the daemon's `PasteboardObserver.tick()`
    /// recognises it as our own and skips re-capturing the content as a
    /// new history record. The sentinel UTI is the same one
    /// `ClipboardXPCService.markAsDaemonWrite()` uses.
    static func markAsLocalWrite(_ pasteboard: NSPasteboard) {
        pasteboard.setData(Data([0]), forType: PasteboardUTI.daemonWrite)
    }

    /// Strip a clipboard body to a plain string. Returns nil for kinds that
    /// have no meaningful text representation (images).
    static func plainString(from body: ClipboardRecord) -> String? {
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

    /// Sub-model bridges — same body, different name so the originals stay
    /// `private static` on the facade for the historical call sites.
    static func markAsLocalWriteForSubModels(_ pasteboard: NSPasteboard) {
        markAsLocalWrite(pasteboard)
    }

    static func plainStringForSubModels(from body: ClipboardRecord) -> String? {
        plainString(from: body)
    }
}
