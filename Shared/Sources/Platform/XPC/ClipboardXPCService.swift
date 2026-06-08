import AppKit
import Core
import Foundation

@objc public final class ClipboardXPCService: NSObject, ClipboardXPCProtocol {
    private let clip: ClipboardStore
    private let blobs: BlobStore
    private let search: SearchStore
    private let snippets: SnippetStore
    private let pinboards: PinboardStore?
    private let pasteboard: NSPasteboard
    private let thumbnailCache = ThumbnailCache()

    public init(
        clip: ClipboardStore,
        blobs: BlobStore,
        search: SearchStore,
        snippets: SnippetStore,
        pinboards: PinboardStore? = nil,
        pasteboard: NSPasteboard = .general
    ) {
        self.clip = clip
        self.blobs = blobs
        self.search = search
        self.snippets = snippets
        self.pinboards = pinboards
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
            let window = ClipboardHistoryWindow.listParameters()
            let metas: [ClipboardItemMeta]
            let nextPageToken: String?
            if let trimmedQuery, !trimmedQuery.isEmpty {
                let hits = try search.search(query: trimmedQuery, limit: pageSize, offset: offset)
                var resolved = try clip.metas(for: hits.map(\.id))
                if let cutoff = window.modifiedOnOrAfter {
                    resolved = resolved.filter { $0.modified >= cutoff }
                }
                metas = resolved
                nextPageToken = hits.count == pageSize ? String(offset + hits.count) : nil
            } else {
                switch historySortMode() {
                case .recency:
                    metas = try clip.list(
                        limit: pageSize, offset: offset, modifiedOnOrAfter: window.modifiedOnOrAfter
                    )
                case .frequency:
                    metas = try clip.recentByFrequency(
                        limit: pageSize, offset: offset, modifiedOnOrAfter: window.modifiedOnOrAfter
                    )
                case .recentlyUsed:
                    metas = try clip.recentByLastAccessed(
                        limit: pageSize, offset: offset, modifiedOnOrAfter: window.modifiedOnOrAfter
                    )
                }
                nextPageToken = metas.count == pageSize ? String(offset + metas.count) : nil
            }
            let items = metas.map { xpcMeta(from: $0) }
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
        try? clip.bumpFrequency(id: rid)
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
            self.performAutoPaste(reply: reply)
        }
    }

    public func pasteMany(
        itemIDs: [String],
        delimiter: String,
        plainText: Bool,
        reply: @escaping (String) -> Void
    ) {
        let recordIDs = itemIDs.compactMap(RecordID.init(rawValue:))
        for rid in recordIDs {
            try? clip.bumpFrequency(id: rid)
        }

        let parts = recordIDs.compactMap { rid -> String? in
            guard let body = try? clip.body(for: rid) else { return nil }
            return Self.plainText(from: body)
        }
        let joined = parts.joined(separator: delimiter)
        DispatchQueue.main.async {
            self.pasteboard.clearContents()
            self.pasteboard.setString(joined, forType: .string)
            self.markAsDaemonWrite()
            self.performAutoPaste(reply: reply)
        }
    }

    public func pasteText(
        text: String,
        plainText: Bool,
        saveAsNew: Bool,
        reply: @escaping (String) -> Void
    ) {
        // Honor capture-suspend on the saveAsNew side so a snippet paste
        // during a suspend window does not silently create a history entry.
        // The pasteboard write itself still happens — suspend pauses *capture*,
        // not the user-initiated output that triggered the paste.
        if saveAsNew, !Self.isCaptureSuspended(),
           let meta = try? clip.append(.text(text), sourceAppBundleID: "com.macallyouneed.app") {
            try? search.upsert(kind: .clipboardItem, id: meta.id, text: text)
        }
        DispatchQueue.main.async {
            self.pasteboard.clearContents()
            self.pasteboard.setString(text, forType: .string)
            self.markAsDaemonWrite()
            self.performAutoPaste(reply: reply)
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
        try? clip.bumpFrequency(id: rid)

        pasteText(text: transformed, plainText: true, saveAsNew: saveAsNew) { _ in
            reply(transformed)
        }
    }

    public func deleteItem(id: String, reply: @escaping (Bool) -> Void) {
        guard let rid = RecordID(rawValue: id) else {
            reply(false)
            return
        }

        do {
            try deleteRecordFully(id: rid)
            reply(true)
        } catch {
            reply(false)
        }
    }

    /// Manual "Clear Older Than N Days" entry point. Daemon owns the writer
    /// lock on the SQLite files, so the main app routes the request through
    /// XPC instead of opening a competing connection. Pinned items are exempt
    /// when a PinboardStore was injected.
    public func runRetention(maxAgeDays: Int, reply: @escaping (Bool) -> Void) {
        guard maxAgeDays > 0 else {
            reply(false)
            return
        }
        let policy = RetentionPolicy(
            maxItems: nil,
            maxAgeSeconds: Double(maxAgeDays) * 86400,
            maxImageBytes: nil
        )
        let protected: Set<RecordID>
        if let pinboards {
            protected = (try? PinboardStore.protectedIDs(from: pinboards)) ?? []
        } else {
            protected = []
        }
        do {
            try policy.enforceMaxAge(
                store: clip, blobs: blobs, search: search, protectedIDs: protected
            )
            reply(true)
        } catch {
            reply(false)
        }
    }

    /// Removes a clipboard record everywhere it touches:
    /// - blob file (for image kinds), so BlobStore doesn't accumulate orphans
    /// - search index row, so FTS doesn't return tombstoned IDs
    /// - clipboard_records row
    /// Throws if the record doesn't exist (caller treats this as "false" reply).
    /// Used by deleteItem RPC and by retention cleanup paths.
    public func deleteRecordFully(id: RecordID) throws {
        let body = try clip.body(for: id)
        if case let .image(blobID, _, _) = body {
            try? blobs.delete(id: blobID)
        }
        try? search.remove(kind: .clipboardItem, id: id)
        try clip.delete(id: id)
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
           meta.preview.hasPrefix("(image "),
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
            imageBlobID: imgBlobID,
            customLabel: meta.customLabel,
            detectedTypeJSON: meta.detectedTypeJSON,
            ocrText: meta.ocrText
        )
    }

    static func plainText(from body: ClipboardRecord) -> String? {
        switch body {
        case let .text(s): return s
        case let .html(s):
            if let data = s.data(using: .utf8),
               let attributed = NSAttributedString(html: data, documentAttributes: nil) {
                return attributed.string.trimmingCharacters(in: .newlines)
            }
            return s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        case let .rtf(data): return NSAttributedString(rtf: data, documentAttributes: nil)?.string
        case let .files(urls): return urls.map(\.path).joined(separator: "\n")
        case .image: return nil
        }
    }

    public static func restoreToPasteboard(body: ClipboardRecord, blobs: BlobStore, pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        switch body {
        case let .text(s): pasteboard.setString(s, forType: .string)
        case let .html(s):
            let plain = plainText(from: .html(s)) ?? s
            pasteboard.setString(plain, forType: .string)
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

    private enum HistorySortMode: String {
        case recency
        case frequency
        case recentlyUsed
    }

    private func historySortMode() -> HistorySortMode {
        let value = AppGroupSettings.defaults.string(forKey: "history.sortMode") ?? ""
        return HistorySortMode(rawValue: value) ?? .recency
    }

    private func performAutoPaste(reply: @escaping (String) -> Void) {
        let behavior = AppGroupSettings.defaults.string(forKey: "autoPaste.behavior") ?? "pasteIntoFocused"
        let delayMs = max(0, AppGroupSettings.defaults.integer(forKey: "autoPaste.delayMs"))

        switch behavior {
        case "copyOnly":
            reply(PasteResult.injected.rawValue)
        case "copyThenPaste":
            let deadline = DispatchTime.now() + .milliseconds(delayMs)
            DispatchQueue.main.asyncAfter(deadline: deadline) {
                let result = PasteInjector.paste(nil, mode: .formatted, into: self.pasteboard)
                reply(result.rawValue)
            }
        default:
            let result = PasteInjector.paste(nil, mode: .formatted, into: self.pasteboard)
            reply(result.rawValue)
        }
    }

    /// Mirrors `DaemonContainer.isCaptureSuspended`. Read inline rather than
    /// injected so the service has no opinion on settings ownership.
    private static func isCaptureSuspended(now: Date = Date()) -> Bool {
        guard let until = AppGroupSettings.defaults.object(forKey: "captureSuspendUntil") as? Double else {
            return false
        }
        return now.timeIntervalSince1970 < until
    }
}
