import Foundation

public final class ClipboardXPCClient {
    public static let machServiceName = "group.com.macallyouneed.shared.daemon"
    public let connection: NSXPCConnection
    private var isResumed = false

    public init(serviceName: String = ClipboardXPCClient.machServiceName, resumesImmediately: Bool = true) {
        connection = NSXPCConnection(machServiceName: serviceName, options: [])
        let iface = NSXPCInterface(with: ClipboardXPCProtocol.self)
        connection.remoteObjectInterface = iface
        let allowed = NSSet(array: [
            ClipboardXPCList.self,
            ClipboardXPCMeta.self,
            ClipboardXPCBlobRef.self,
            NSArray.self,
            NSString.self,
            NSDate.self,
            NSNumber.self
        ]) as! Set<AnyHashable>
        iface.setClasses(
            allowed,
            for: #selector(ClipboardXPCProtocol.listItems(query:pageToken:limit:reply:)),
            argumentIndex: 0, ofReply: true
        )
        iface.setClasses(
            allowed,
            for: #selector(ClipboardXPCProtocol.resolveBlob(blobID:reply:)),
            argumentIndex: 0, ofReply: true
        )
        if resumesImmediately {
            resume()
        }
    }

    public func resume() {
        guard !isResumed else { return }
        connection.resume()
        isResumed = true
    }

    public func proxy() -> ClipboardXPCProtocol? {
        connection.remoteObjectProxyWithErrorHandler { err in
            Logging.logger(for: "xpc", category: "client").error("XPC error: \(err.localizedDescription)")
        } as? ClipboardXPCProtocol
    }
}
