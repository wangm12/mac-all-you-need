import AppKit
import Core
import CryptoKit
import Foundation
import Platform
import Security


final class DaemonContainer {
    let key: SymmetricKey
    let deviceID: DeviceID
    let clipDB: Database
    let clip: ClipboardStore
    let searchDB: Database
    let search: SearchStore
    let blobs: BlobStore
    let snippetDB: Database
    let snippets: SnippetStore
    let observer: PasteboardObserver
    let expander: SnippetExpander
    let log = Logging.logger(for: "daemon", category: "container")

    init() throws {
        let root = AppGroup.containerURL().appendingPathComponent("databases", isDirectory: true)
        let blobRoot = AppGroup.containerURL().appendingPathComponent("blobs", isDirectory: true)
        let manager = KeyManager(keychain: SystemKeychain())
        key = try manager.deviceKey()
        deviceID = try DeviceIdentityStore.loadOrCreate(root: AppGroup.containerURL())
        clipDB = try Database(
            url: root.appendingPathComponent("clipboard.sqlite"),
            migrations: ClipboardStore.migrations
        )
        clip = try ClipboardStore(database: clipDB, deviceKey: key, deviceID: deviceID)
        searchDB = try Database(
            url: root.appendingPathComponent("search.sqlite"),
            migrations: SearchStore.migrations
        )
        search = SearchStore(database: searchDB)
        blobs = BlobStore(rootURL: blobRoot, key: key)
        snippetDB = try Database(
            url: root.appendingPathComponent("snippets.sqlite"),
            migrations: SnippetStore.migrations
        )
        snippets = SnippetStore(database: snippetDB, deviceKey: key)
        observer = PasteboardObserver(reader: SystemPasteboardReader(), rules: ExclusionRules())
        expander = SnippetExpander { [snippets] trigger in
            try? snippets.find(trigger: trigger)?.body
        }
        expander.start()
    }

    func persist(item: PasteboardItem, source: String?) throws {
        switch item {
        case let .text(s):
            let meta = try clip.append(.text(s), sourceAppBundleID: source)
            try search.upsert(kind: .clipboardItem, id: meta.id, text: s)
        case let .rtf(d):
            let meta = try clip.append(.rtf(d), sourceAppBundleID: source)
            if let s = NSAttributedString(rtf: d, documentAttributes: nil)?.string {
                try search.upsert(kind: .clipboardItem, id: meta.id, text: s)
            }
        case let .html(s):
            let meta = try clip.append(.html(s), sourceAppBundleID: source)
            try search.upsert(kind: .clipboardItem, id: meta.id, text: s)
        case let .png(d), let .tiff(d):
            let blobID = try blobs.write(d)
            let nsImg = NSImage(data: d)
            let w = Int(nsImg?.size.width ?? 0)
            let h = Int(nsImg?.size.height ?? 0)
            let meta = try clip.append(.image(blobID: blobID, width: w, height: h), sourceAppBundleID: source)
            Task.detached { [search] in
                if let png = Self.pngData(from: d),
                   let text = try? await OCRService.recognize(pngData: png), !text.isEmpty
                {
                    try? search.upsert(kind: .clipboardItem, id: meta.id, text: text)
                }
            }
        case let .fileURLs(urls):
            let meta = try clip.append(.files(urls), sourceAppBundleID: source)
            try search.upsert(
                kind: .clipboardItem,
                id: meta.id,
                text: urls.map(\.lastPathComponent).joined(separator: " ")
            )
        case .unknown:
            break
        }
    }

    private static func pngData(from data: Data) -> Data? {
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
