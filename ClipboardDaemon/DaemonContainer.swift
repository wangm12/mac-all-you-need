import AppKit
import Core
import CryptoKit
import Foundation
import Platform
import Security

enum DeviceIdentityStore {
    static func loadOrCreate(root: URL) throws -> DeviceID {
        let url = root.appendingPathComponent("device-id.txt")
        if let raw = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           let id = DeviceID(rawValue: raw) { return id }
        let id = DeviceID.generate()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try id.rawValue.write(to: url, atomically: true, encoding: .utf8)
        return id
    }
}

final class DaemonContainer {
    let key: SymmetricKey
    let deviceID: DeviceID
    let clipDB: Database
    let clip: ClipboardStore
    let searchDB: Database
    let search: SearchStore
    let blobs: BlobStore
    let observer: PasteboardObserver
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
        observer = PasteboardObserver(reader: SystemPasteboardReader(), rules: ExclusionRules())
    }

    func persist(item: PasteboardItem, source: String?) throws {
        switch item {
        case .text(let s):
            let meta = try clip.append(.text(s), sourceAppBundleID: source)
            try search.upsert(kind: .clipboardItem, id: meta.id, text: s)
        case .rtf(let d):
            let meta = try clip.append(.rtf(d), sourceAppBundleID: source)
            if let s = NSAttributedString(rtf: d, documentAttributes: nil)?.string {
                try search.upsert(kind: .clipboardItem, id: meta.id, text: s)
            }
        case .html(let s):
            let meta = try clip.append(.html(s), sourceAppBundleID: source)
            try search.upsert(kind: .clipboardItem, id: meta.id, text: s)
        case .png(let d), .tiff(let d):
            let blobID = try blobs.write(d)
            let nsImg = NSImage(data: d)
            let w = Int(nsImg?.size.width ?? 0)
            let h = Int(nsImg?.size.height ?? 0)
            let meta = try clip.append(.image(blobID: blobID, width: w, height: h), sourceAppBundleID: source)
            Task.detached { [search] in
                if let png = Self.pngData(from: d),
                   let text = try? await OCRService.recognize(pngData: png), !text.isEmpty {
                    try? search.upsert(kind: .clipboardItem, id: meta.id, text: text)
                }
            }
        case .fileURLs(let urls):
            let meta = try clip.append(.files(urls), sourceAppBundleID: source)
            try search.upsert(kind: .clipboardItem, id: meta.id,
                              text: urls.map(\.lastPathComponent).joined(separator: " "))
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
