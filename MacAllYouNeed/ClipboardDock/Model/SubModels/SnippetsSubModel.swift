import AppKit
import Core
import Foundation
import Platform

/// Snippets slice extracted from `ClipboardDockModel`. Owns CRUD against the
/// `SnippetStore`, focused-snippet operations, pasteboard copy, and the
/// clipboard-to-snippet draft flow.
///
/// All published state (`snippetItems`, `pendingSnippetDraft`, `focusedIndex`,
/// `activeList`) is held on the facade `ClipboardDockModel` so SwiftUI
/// observation behavior is preserved exactly. This sub-model is a behavior
/// collaborator — it mutates the facade's state through an `unowned` back
/// reference.
@MainActor
final class SnippetsSubModel {
    private unowned let model: ClipboardDockModel
    let store: SnippetStore

    init(model: ClipboardDockModel, store: SnippetStore) {
        self.model = model
        self.store = store
    }

    func loadSnippets() async {
        let store = self.store
        let loaded = await Task.detached(priority: .userInitiated) {
            (try? store.list()) ?? []
        }.value
        model.snippetItems = loaded
        if model.activeList == .snippets {
            model.focusedIndex = loaded.isEmpty
                ? ClipboardDockModel.noCardFocus
                : (model.focusedIndex < 0
                    ? ClipboardDockModel.noCardFocus
                    : min(model.focusedIndex, loaded.count - 1))
        }
    }

    func createSnippet(name: String, body: String, trigger: String?) async throws {
        try store.create(name: name, body: body, trigger: trigger)
        await loadSnippets()
    }

    func updateSnippet(id: RecordID, name: String, body: String, trigger: String?) async throws {
        try store.update(id: id, name: name, body: body, trigger: trigger)
        await loadSnippets()
    }

    func deleteSnippet(id: RecordID) async {
        try? store.delete(id: id)
        await loadSnippets()
    }

    func duplicateSnippet(id: RecordID) async {
        guard let original = model.snippetItems.first(where: { $0.id == id }) else { return }
        _ = try? store.create(
            name: "\(original.name) (copy)",
            body: original.body,
            trigger: nil
        )
        await loadSnippets()
    }

    func pasteSnippet(id: RecordID, plainText: Bool) async {
        guard let snippet = model.snippetItems.first(where: { $0.id == id }) else { return }
        _ = await model.xpc.pasteText(text: snippet.body, plainText: plainText, saveAsNew: true)
    }

    func pasteFocusedSnippet(plainText: Bool) async {
        guard model.activeList == .snippets,
              model.snippetItems.indices.contains(model.focusedIndex)
        else { return }
        await pasteSnippet(id: model.snippetItems[model.focusedIndex].id, plainText: plainText)
    }

    func copySnippet(id: RecordID) {
        guard let snippet = model.snippetItems.first(where: { $0.id == id }) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snippet.body, forType: .string)
        ClipboardDockModel.markAsLocalWriteForSubModels(.general)
    }

    func copyFocusedSnippet() {
        guard model.activeList == .snippets,
              model.snippetItems.indices.contains(model.focusedIndex)
        else { return }
        copySnippet(id: model.snippetItems[model.focusedIndex].id)
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
            model.triggerFeedback("Snippet needs text", symbol: "exclamationmark.triangle.fill")
            return false
        }

        model.pendingSnippetDraft = SnippetDraft(
            name: "Clipboard snippet",
            body: bodies.joined(separator: "\n")
        )
        return true
    }

    func clearPendingSnippetDraft() {
        model.pendingSnippetDraft = nil
    }

    /// Resolve a clipboard record's plain-text body — preferring the in-process
    /// clipboard store when available, falling back to XPC. Returns nil if the
    /// body has no useful text representation.
    func snippetBody(forClipboardItemID itemID: String) async -> String? {
        if let rid = RecordID(rawValue: itemID),
           let clip = model.clip,
           let record = try? clip.body(for: rid),
           let body = ClipboardDockModel.plainStringForSubModels(from: record),
           !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return body
        }

        guard let body = await model.xpc.bodyText(forID: itemID),
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return body
    }
}
