import AppKit
import Core
import SwiftUI

/// Right-click context menu attached to every clipboard card. Items reuse
/// existing model methods + the `dockPasteRequested` notification so the
/// menu doesn't need a direct reference to `DockWindowController`.
struct CardContextMenu: View {
    let item: DockItem
    @Bindable var model: ClipboardDockModel
    @Binding var renamingItemID: String?

    var body: some View {
        Button("Paste to \(targetAppName)") {
            requestPaste(plainText: false)
        }
        Button("Paste as Plain Text") {
            requestPaste(plainText: true)
        }
        Button("Copy") {
            Task { await model.copyToClipboard(itemID: item.id) }
        }

        Divider()

        // Flat "Pin to <list>" entries — one per pinboard, including the
        // auto-created "Pinned" list (it's no longer special). Submenus
        // inside a contextMenu hosted in a borderless nonactivating NSPanel
        // intermittently swallow clicks.
        ForEach(model.availableLists, id: \.id) { board in
            Button("Pin to \(board.name)") {
                Task {
                    await model.addToPinboard(itemIDs: [item.id], boardID: board.id)
                    await model.loadAvailableLists()
                }
            }
        }
        Button("Rename…") {
            renamingItemID = item.id
        }
        Button("Delete", role: .destructive) {
            Task { await model.deleteItem(itemID: item.id) }
        }

        Divider()

        Button("Quick Look") {
            // Focus the right card so QuickLookOverlay shows this one.
            if let idx = model.items.firstIndex(where: { $0.id == item.id }) {
                model.focusedIndex = idx
            }
            model.isQuickLooking = true
        }
        Button("Share…") {
            shareItem()
        }
    }

    private var targetAppName: String {
        guard let bid = model.previousFrontmostBundleID else { return "Frontmost App" }
        return model.appIcons.displayName(for: bid)
    }

    private func requestPaste(plainText: Bool) {
        NotificationCenter.default.post(
            name: .dockPasteRequested,
            object: DockPasteIntent(itemID: item.id, plainText: plainText)
        )
    }

    /// Build a sharable payload from the card's body and present
    /// NSSharingServicePicker anchored to the key window's content view.
    private func shareItem() {
        guard let clip = model.clip,
              let rid = RecordID(rawValue: item.id),
              let body = try? clip.body(for: rid)
        else { return }

        var payload: [Any] = []
        switch body {
        case let .text(s): payload = [s as NSString]
        case let .html(s): payload = [s as NSString]
        case let .rtf(data):
            if let attr = NSAttributedString(rtf: data, documentAttributes: nil) {
                payload = [attr.string as NSString]
            }
        case let .image(blobID, _, _):
            if let blobs = model.blobs,
               let data = try? blobs.read(id: blobID),
               let img = NSImage(data: data)
            {
                payload = [img]
            }
        case let .files(urls):
            payload = urls as [Any]
        }
        guard !payload.isEmpty else { return }

        let picker = NSSharingServicePicker(items: payload)
        guard let anchor = NSApp.keyWindow?.contentView else { return }
        picker.show(relativeTo: .zero, of: anchor, preferredEdge: .minY)
    }
}
