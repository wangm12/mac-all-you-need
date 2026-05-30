import AppKit
import Core
import Platform
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

        typeAwareEntries

        if let videoURL = URLDetector.videoBearingURL(in: item.preview) {
            Divider()
            Button {
                NotificationCenter.default.post(name: .clipboardDownloadRequested, object: videoURL)
            } label: {
                Label("Download Video", systemImage: "arrow.down.circle")
            }
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
            if let idx = model.items.firstIndex(where: { $0.id == item.id }) {
                model.focusedIndex = idx
            }
            showQuickLook()
        }
        Button("Share…") {
            shareItem()
        }
    }

    /// Type-aware actions derived from Smart Text detection: email Compose,
    /// phone Call / Copy digits, JWT Decode. Hidden when detection is absent or
    /// the type has no specific action.
    @ViewBuilder
    private var typeAwareEntries: some View {
        switch item.detectedTypeName {
        case "email":
            Divider()
            Button("Compose Email") {
                if let url = URL(string: "mailto:\(item.preview.trimmingCharacters(in: .whitespacesAndNewlines))") {
                    NSWorkspace.shared.open(url)
                }
            }
        case "phone":
            Divider()
            let digits = item.preview.filter { $0.isNumber || $0 == "+" }
            Button("Call") {
                if let url = URL(string: "tel:\(digits)") { NSWorkspace.shared.open(url) }
            }
            Button("Copy Digits") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(digits, forType: .string)
            }
        case "jwt":
            Divider()
            Button("Decode JWT") { decodeJWT() }
        default:
            EmptyView()
        }
    }

    private func decodeJWT() {
        let parts = item.preview.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return }
        let decoded = parts.prefix(2).compactMap { part -> String? in
            var b = String(part).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            while b.count % 4 != 0 { b += "=" }
            guard let data = Data(base64Encoded: b),
                  let obj = try? JSONSerialization.jsonObject(with: data),
                  let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
            else { return nil }
            return String(decoding: pretty, as: UTF8.self)
        }
        let alert = NSAlert()
        alert.messageText = "Decoded JWT"
        alert.informativeText = decoded.joined(separator: "\n\n")
        alert.runModal()
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

    private func showQuickLook() {
        guard let clip = model.clip,
              let rid = RecordID(rawValue: item.id),
              let body = try? clip.body(for: rid)
        else { return }

        ClipboardSystemQuickLookCoordinator.shared.show(
            record: body,
            title: item.displayLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            blobs: model.blobs
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
        case let .html(s):
            if let data = s.data(using: .utf8),
               let attr = NSAttributedString(html: data, documentAttributes: nil) {
                payload = [attr.string.trimmingCharacters(in: .newlines) as NSString]
            } else {
                payload = [s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression) as NSString]
            }
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
