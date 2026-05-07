import AppKit
import Core
import Foundation

@objc public final class ClipboardXPCService: NSObject {
    private let clip: ClipboardStore
    private let blobs: BlobStore
    private let search: SearchStore
    private let snippets: SnippetStore
    private let pasteboard: NSPasteboard

    public init(
        clip: ClipboardStore,
        blobs: BlobStore,
        search: SearchStore,
        snippets: SnippetStore,
        pasteboard: NSPasteboard = .general
    ) {
        self.clip = clip
        self.blobs = blobs
        self.search = search
        self.snippets = snippets
        self.pasteboard = pasteboard
    }

    public func listItems(
        query: String?, pageToken: String?, limit: Int,
        reply: @escaping (ClipboardXPCList) -> Void
    ) {
        do {
            let pageSize = max(1, min(limit, 100))
            let offset = max(0, Int(pageToken ?? "") ?? 0)
            let trimmedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines)
            let metas: [ClipboardItemMeta]
            if let trimmedQuery, !trimmedQuery.isEmpty {
                let hits = try search.search(query: trimmedQuery, limit: pageSize, offset: offset)
                metas = try clip.metas(for: hits.map(\.id))
            } else {
                metas = try clip.list(limit: pageSize, offset: offset)
            }
            let items = metas.map {
                ClipboardXPCMeta(
                    id: $0.id.rawValue,
                    modified: $0.modified,
                    kind: $0.kind.rawValue,
                    preview: $0.preview
                )
            }
            let nextPageToken = items.count == pageSize ? String(offset + items.count) : nil
            reply(ClipboardXPCList(items: items, nextPageToken: nextPageToken))
        } catch {
            reply(ClipboardXPCList(items: [], nextPageToken: nil))
        }
    }

    public func bodyText(forID id: String, reply: @escaping (String?) -> Void) {
        guard let rid = RecordID(rawValue: id) else { reply(nil); return }
        switch try? clip.body(for: rid) {
        case let .text(s), let .html(s): reply(s)
        default: reply(nil)
        }
    }

    public func resolveBlob(blobID: String, reply: @escaping (ClipboardXPCBlobRef?) -> Void) {
        let url = blobs.encryptedURL(id: blobID)
        guard FileManager.default.fileExists(atPath: url.path) else { reply(nil); return }
        reply(ClipboardXPCBlobRef(blobID: blobID, encryptedFilePath: url.path, kind: "encrypted"))
    }

    public func paste(itemID: String, plainText: Bool, reply: @escaping (String) -> Void) {
        guard let rid = RecordID(rawValue: itemID),
              let body = try? clip.body(for: rid)
        else {
            reply(PasteResult.manualPasteRequired.rawValue)
            return
        }
        DispatchQueue.main.async {
            if plainText {
                if let text = Self.plainText(from: body) {
                    self.pasteboard.clearContents()
                    self.pasteboard.setString(text, forType: .string)
                }
            } else {
                Self.restoreToPasteboard(body: body, blobs: self.blobs, pasteboard: self.pasteboard)
            }
            self.markAsDaemonWrite()
            // Always pass .formatted: the service has already written exactly what it wants
            // on the pasteboard. PasteInjector(.plainText) would clearContents() again and
            // strip our sentinel UTI, re-enabling the duplicate-history bug.
            let result = PasteInjector.paste(nil, mode: .formatted, into: self.pasteboard)
            reply(result.rawValue)
        }
    }

    public func listSnippets(reply: @escaping ([SnippetXPCDTO]) -> Void) {
        let rows = (try? snippets.list()) ?? []
        reply(rows.map { SnippetXPCDTO(id: $0.id.rawValue, name: $0.name, trigger: $0.trigger) })
    }

    static func plainText(from body: ClipboardRecord) -> String? {
        switch body {
        case let .text(s): return s
        case let .html(s):
            if let data = s.data(using: .utf8),
               let attributed = NSAttributedString(html: data, documentAttributes: nil) {
                return attributed.string
            }
            return s
        case let .rtf(data): return NSAttributedString(rtf: data, documentAttributes: nil)?.string
        case let .files(urls): return urls.map(\.path).joined(separator: "\n")
        case .image: return nil
        }
    }

    static func restoreToPasteboard(body: ClipboardRecord, blobs: BlobStore, pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        switch body {
        case let .text(s): pasteboard.setString(s, forType: .string)
        case let .html(s):
            pasteboard.setString(s, forType: NSPasteboard.PasteboardType.html)
            pasteboard.setString(s, forType: .string)
        case let .rtf(data):
            pasteboard.setData(data, forType: .rtf)
            if let s = NSAttributedString(rtf: data, documentAttributes: nil)?.string {
                pasteboard.setString(s, forType: .string)
            }
        case let .image(blobID, _, _):
            if let data = try? blobs.read(id: blobID) { pasteboard.setData(data, forType: .png) }
        case let .files(urls): pasteboard.writeObjects(urls as [NSURL])
        }
    }

    /// Stub — real implementation lands in Task 1.5 (self-write suppression).
    private func markAsDaemonWrite() {}
}
