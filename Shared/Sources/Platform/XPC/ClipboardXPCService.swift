import AppKit
import Core
import Foundation

@objc public final class ClipboardXPCService: NSObject, ClipboardXPCProtocol {
    private let clip: ClipboardStore
    private let blobs: BlobStore
    private let search: SearchStore
    private let snippets: SnippetStore
    private let pasteboard: NSPasteboard
    private let thumbnailCache = ThumbnailCache()

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
            let items = metas.map { xpcMeta(from: $0) }
            let nextPageToken = items.count == pageSize ? String(offset + items.count) : nil
            reply(ClipboardXPCList(items: items, nextPageToken: nextPageToken))
        } catch {
            reply(ClipboardXPCList(items: [], nextPageToken: nil))
        }
    }

    public func metasByIDs(ids: [String], reply: @escaping (ClipboardXPCList) -> Void) {
        let recordIDs = ids.compactMap { RecordID(rawValue: $0) }
        let metas = (try? clip.metas(for: recordIDs)) ?? []
        let items = metas.map { xpcMeta(from: $0) }
        reply(ClipboardXPCList(items: items, nextPageToken: nil))
    }

    public func bodyText(forID id: String, reply: @escaping (String?) -> Void) {
        guard let rid = RecordID(rawValue: id) else { reply(nil); return }
        switch try? clip.body(for: rid) {
        case let .text(s), let .html(s): reply(s)
        default: reply(nil)
        }
    }

    public func bodyFileURLs(forID id: String, reply: @escaping ([String]?) -> Void) {
        guard let rid = RecordID(rawValue: id),
              let body = try? clip.body(for: rid),
              case let .files(urls) = body
        else {
            reply(nil)
            return
        }
        reply(urls.map(\.path))
    }

    public func resolveBlob(blobID: String, reply: @escaping (ClipboardXPCBlobRef?) -> Void) {
        let url = blobs.encryptedURL(id: blobID)
        guard FileManager.default.fileExists(atPath: url.path) else { reply(nil); return }
        reply(ClipboardXPCBlobRef(blobID: blobID, encryptedFilePath: url.path, kind: "encrypted"))
    }

    public func imageThumbnail(forID id: String, maxDim: Int, reply: @escaping (Data?) -> Void) {
        guard let rid = RecordID(rawValue: id),
              let body = try? clip.body(for: rid),
              case let .image(blobID, _, _) = body
        else {
            reply(nil)
            return
        }

        if let cached = thumbnailCache.value(blobID: blobID, maxDim: maxDim) {
            reply(cached)
            return
        }

        guard let raw = try? blobs.read(id: blobID),
              let rendered = ThumbnailRenderer.render(data: raw, maxDim: maxDim)
        else {
            reply(nil)
            return
        }

        thumbnailCache.set(rendered, blobID: blobID, maxDim: maxDim)
        reply(rendered)
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

    public func pasteMany(
        itemIDs: [String],
        delimiter: String,
        plainText: Bool,
        reply: @escaping (String) -> Void
    ) {
        let parts = itemIDs.compactMap { idString -> String? in
            guard let rid = RecordID(rawValue: idString),
                  let body = try? clip.body(for: rid)
            else {
                return nil
            }
            return Self.plainText(from: body)
        }
        let joined = parts.joined(separator: delimiter)
        DispatchQueue.main.async {
            self.pasteboard.clearContents()
            self.pasteboard.setString(joined, forType: .string)
            self.markAsDaemonWrite()
            // The service already wrote final plain text to the pasteboard.
            // Using .plainText would clearContents() and remove the sentinel.
            let result = PasteInjector.paste(nil, mode: .formatted, into: self.pasteboard)
            reply(result.rawValue)
        }
    }

    public func pasteText(
        text: String,
        plainText: Bool,
        saveAsNew: Bool,
        reply: @escaping (String) -> Void
    ) {
        if saveAsNew,
           let meta = try? clip.append(.text(text), sourceAppBundleID: "com.macallyouneed.app") {
            try? search.upsert(kind: .clipboardItem, id: meta.id, text: text)
        }
        DispatchQueue.main.async {
            self.pasteboard.clearContents()
            self.pasteboard.setString(text, forType: .string)
            self.markAsDaemonWrite()
            // The service already wrote the final string and needs to keep sentinel intact.
            let result = PasteInjector.paste(nil, mode: .formatted, into: self.pasteboard)
            reply(result.rawValue)
        }
    }

    public func transformAndCopy(
        itemID: String,
        transform: String,
        saveAsNew: Bool,
        reply: @escaping (String?) -> Void
    ) {
        guard let transformKind = TextTransform(rawValue: transform),
              let rid = RecordID(rawValue: itemID),
              let body = try? clip.body(for: rid),
              let sourceText = Self.plainText(from: body),
              let transformed = TextTransforms.apply(transformKind, to: sourceText)
        else {
            reply(nil)
            return
        }

        pasteText(text: transformed, plainText: true, saveAsNew: saveAsNew) { _ in
            reply(transformed)
        }
    }

    public func listSnippets(reply: @escaping ([SnippetXPCDTO]) -> Void) {
        let rows = (try? snippets.list()) ?? []
        reply(rows.map { SnippetXPCDTO(id: $0.id.rawValue, name: $0.name, trigger: $0.trigger) })
    }

    public func registerCallback(reply: @escaping (Bool) -> Void) {
        reply(false)
    }

    private func xpcMeta(from meta: ClipboardItemMeta) -> ClipboardXPCMeta {
        var imgWidth = 0
        var imgHeight = 0
        var imgBlobID: String?
        if meta.kind == .clipboardItem,
           let body = try? clip.body(for: meta.id),
           case let .image(blobID, w, h) = body {
            imgBlobID = blobID
            imgWidth = w
            imgHeight = h
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

    private func markAsDaemonWrite() {
        pasteboard.setData(Data([0]), forType: PasteboardUTI.daemonWrite)
    }
}
