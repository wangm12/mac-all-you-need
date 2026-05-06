import AppKit
import Core
import Foundation
import Platform
import Security

final class ClipboardXPCServer: NSObject, ClipboardXPCProtocol, NSXPCListenerDelegate {
    let container: DaemonContainer
    let listener: NSXPCListener
    private var callbacks: [ObjectIdentifier: ClipboardXPCClientCallback] = [:]
    private let callbackLock = NSLock()

    init(container: DaemonContainer) {
        self.container = container
        listener = NSXPCListener(machServiceName: ClipboardXPCClient.machServiceName)
        super.init()
        listener.delegate = self
        listener.resume()
    }

    func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard Self.isAllowedClient(newConnection) else {
            container.log.warning("Rejected XPC client pid=\(newConnection.processIdentifier)")
            return false
        }
        let iface = NSXPCInterface(with: ClipboardXPCProtocol.self)
        let allowed: NSSet = [
            ClipboardXPCList.self,
            ClipboardXPCBlobRef.self,
            NSArray.self,
            ClipboardXPCMeta.self,
            NSString.self,
            NSDate.self
        ]
        iface.setClasses(
            allowed as! Set<AnyHashable>,
            for: #selector(ClipboardXPCProtocol.listItems(query:pageToken:limit:reply:)),
            argumentIndex: 0,
            ofReply: true
        )
        iface.setClasses(
            allowed as! Set<AnyHashable>,
            for: #selector(ClipboardXPCProtocol.resolveBlob(blobID:reply:)),
            argumentIndex: 0,
            ofReply: true
        )
        newConnection.exportedInterface = iface
        newConnection.exportedObject = self
        newConnection.remoteObjectInterface = NSXPCInterface(with: ClipboardXPCClientCallback.self)
        newConnection.invalidationHandler = { [weak self, weak newConnection] in
            guard let self, let conn = newConnection else { return }
            let key = ObjectIdentifier(conn)
            callbackLock.lock(); callbacks.removeValue(forKey: key); callbackLock.unlock()
        }
        newConnection.resume()
        return true
    }

    static func isAllowedClient(_ connection: NSXPCConnection) -> Bool {
        let allowedBundleIDs: Set = ["com.macallyouneed.app"]
        let allowedTeamID = Bundle.main.object(forInfoDictionaryKey: "MAYNTeamIdentifier") as? String
        guard let app = NSRunningApplication(processIdentifier: connection.processIdentifier),
              let bundleID = app.bundleIdentifier,
              allowedBundleIDs.contains(bundleID) else { return false }
        guard let allowedTeamID else { return true }
        return CodeSignatureIdentity.teamIdentifier(for: app) == allowedTeamID
    }

    enum CodeSignatureIdentity {
        static func teamIdentifier(for app: NSRunningApplication) -> String? {
            guard let url = app.bundleURL else { return nil }
            var code: SecStaticCode?
            guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
            var info: CFDictionary?
            guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
                  let dict = info as? [String: Any] else { return nil }
            return dict[kSecCodeInfoTeamIdentifier as String] as? String
        }
    }

    func notifyInvalidated() {
        callbackLock.lock(); let snapshot = Array(callbacks.values); callbackLock.unlock()
        for cb in snapshot {
            cb.itemsInvalidated()
        }
    }

    func registerCallback(reply: @escaping (Bool) -> Void) {
        if let conn = NSXPCConnection.current(),
           let proxy = conn.remoteObjectProxy as? ClipboardXPCClientCallback
        {
            callbackLock.lock()
            callbacks[ObjectIdentifier(conn)] = proxy
            callbackLock.unlock()
            reply(true)
        } else { reply(false) }
    }

    func listItems(query _: String?, pageToken _: String?, limit: Int, reply: @escaping (ClipboardXPCList) -> Void) {
        do {
            let metas = try container.clip.list(limit: limit)
            let items = metas.map {
                ClipboardXPCMeta(id: $0.id.rawValue, modified: $0.modified, kind: $0.kind.rawValue, preview: $0.preview)
            }
            reply(ClipboardXPCList(items: items, nextPageToken: nil))
        } catch {
            reply(ClipboardXPCList(items: [], nextPageToken: nil))
        }
    }

    func bodyText(forID id: String, reply: @escaping (String?) -> Void) {
        guard let rid = RecordID(rawValue: id) else { reply(nil); return }
        switch try? container.clip.body(for: rid) {
        case let .text(s), let .html(s): reply(s)
        default: reply(nil)
        }
    }

    func resolveBlob(blobID: String, reply: @escaping (ClipboardXPCBlobRef?) -> Void) {
        let url = container.blobs.encryptedURL(id: blobID)
        guard FileManager.default.fileExists(atPath: url.path) else { reply(nil); return }
        reply(ClipboardXPCBlobRef(blobID: blobID, encryptedFilePath: url.path, kind: "encrypted"))
    }

    func paste(itemID: String, plainText: Bool, reply: @escaping (String) -> Void) {
        guard let rid = RecordID(rawValue: itemID),
              let body = try? container.clip.body(for: rid)
        else {
            reply(PasteResult.manualPasteRequired.rawValue)
            return
        }
        DispatchQueue.main.async {
            if plainText {
                if let text = Self.plainText(from: body) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            } else {
                Self.restoreToPasteboard(body: body, blobs: self.container.blobs)
            }
            let result = PasteInjector.paste(nil, mode: plainText ? .plainText : .formatted)
            reply(result.rawValue)
        }
    }

    private static func plainText(from body: ClipboardRecord) -> String? {
        switch body {
        case let .text(s), let .html(s): s
        case let .rtf(data): NSAttributedString(rtf: data, documentAttributes: nil)?.string
        case let .files(urls): urls.map(\.path).joined(separator: "\n")
        case .image: nil
        }
    }

    private static func restoreToPasteboard(body: ClipboardRecord, blobs: BlobStore) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch body {
        case let .text(s): pb.setString(s, forType: .string)
        case let .html(s):
            pb.setString(s, forType: NSPasteboard.PasteboardType.html)
            pb.setString(s, forType: .string)
        case let .rtf(data):
            pb.setData(data, forType: .rtf)
            if let s = NSAttributedString(rtf: data, documentAttributes: nil)?.string { pb.setString(s, forType: .string) }
        case let .image(blobID, _, _):
            if let data = try? blobs.read(id: blobID) { pb.setData(data, forType: .png) }
        case let .files(urls): pb.writeObjects(urls as [NSURL])
        }
    }
}
