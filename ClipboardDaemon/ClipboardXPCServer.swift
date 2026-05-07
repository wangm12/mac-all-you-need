import AppKit
import Core
import Foundation
import Platform

final class ClipboardXPCServer: NSObject, ClipboardXPCProtocol, NSXPCListenerDelegate {
    let container: DaemonContainer
    let listener: NSXPCListener
    let service: ClipboardXPCService
    private var callbacks: [pid_t: ClipboardXPCClientCallback] = [:]
    private let callbackLock = NSLock()

    init(container: DaemonContainer) {
        self.container = container
        listener = NSXPCListener(machServiceName: ClipboardXPCClient.machServiceName)
        service = ClipboardXPCService(
            clip: container.clip,
            blobs: container.blobs,
            search: container.search,
            snippets: container.snippets
        )
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
        let pid = newConnection.processIdentifier
        newConnection.invalidationHandler = { [weak self] in
            guard let self else { return }
            callbackLock.lock(); callbacks.removeValue(forKey: pid); callbackLock.unlock()
        }
        newConnection.resume()
        return true
    }

    static func isAllowedClient(_ connection: NSXPCConnection) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: connection.processIdentifier) else { return false }
        return app.bundleIdentifier == "com.macallyouneed.app"
    }

    func notifyInvalidated() {
        callbackLock.lock(); let snapshot = Array(callbacks.values); callbackLock.unlock()
        for cb in snapshot { cb.itemsInvalidated() }
    }

    // ClipboardXPCProtocol — delegate to service except registerCallback (XPC-connection state)
    func listItems(query: String?, pageToken: String?, limit: Int, reply: @escaping (ClipboardXPCList) -> Void) {
        service.listItems(query: query, pageToken: pageToken, limit: limit, reply: reply)
    }
    func bodyText(forID id: String, reply: @escaping (String?) -> Void) {
        service.bodyText(forID: id, reply: reply)
    }
    func resolveBlob(blobID: String, reply: @escaping (ClipboardXPCBlobRef?) -> Void) {
        service.resolveBlob(blobID: blobID, reply: reply)
    }
    func paste(itemID: String, plainText: Bool, reply: @escaping (String) -> Void) {
        service.paste(itemID: itemID, plainText: plainText, reply: reply)
    }
    func listSnippets(reply: @escaping ([SnippetXPCDTO]) -> Void) {
        service.listSnippets(reply: reply)
    }

    func registerCallback(reply: @escaping (Bool) -> Void) {
        if let conn = NSXPCConnection.current(),
           let proxy = conn.remoteObjectProxy as? ClipboardXPCClientCallback {
            callbackLock.lock()
            callbacks[conn.processIdentifier] = proxy
            callbackLock.unlock()
            reply(true)
        } else { reply(false) }
    }
}
