import Foundation

public final class ClipboardXPCClient: @unchecked Sendable {
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
            SnippetXPCDTO.self,
            NSArray.self,
            NSString.self,
            NSDate.self,
            NSNumber.self,
            NSData.self
        ]) as! Set<AnyHashable>
        iface.setClasses(
            allowed,
            for: #selector(ClipboardXPCProtocol.listItems(query:pageToken:limit:reply:)),
            argumentIndex: 0, ofReply: true
        )
        iface.setClasses(
            allowed,
            for: #selector(ClipboardXPCProtocol.metasByIDs(ids:reply:)),
            argumentIndex: 0,
            ofReply: true
        )
        iface.setClasses(
            allowed,
            for: #selector(ClipboardXPCProtocol.resolveBlob(blobID:reply:)),
            argumentIndex: 0, ofReply: true
        )
        iface.setClasses(
            allowed,
            for: #selector(ClipboardXPCProtocol.imageThumbnail(forID:maxDim:reply:)),
            argumentIndex: 0, ofReply: true
        )
        iface.setClasses(
            allowed,
            for: #selector(ClipboardXPCProtocol.bodyFileURLs(forID:reply:)),
            argumentIndex: 0,
            ofReply: true
        )
        iface.setClasses(
            allowed,
            for: #selector(ClipboardXPCProtocol.listSnippets(reply:)),
            argumentIndex: 0, ofReply: true
        )
        iface.setClasses(
            allowed,
            for: #selector(ClipboardXPCProtocol.pasteMany(itemIDs:delimiter:plainText:reply:)),
            argumentIndex: 0,
            ofReply: false
        )
        iface.setClasses(
            allowed,
            for: #selector(ClipboardXPCProtocol.metasByIDs(ids:reply:)),
            argumentIndex: 0,
            ofReply: false
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

extension ClipboardXPCClient: ClipboardXPCInteracting {
    public func listItems(query: String?, pageToken: String?, limit: Int) async -> ClipboardXPCList {
        await withCheckedContinuation { cont in
            let empty = ClipboardXPCList(items: [], nextPageToken: nil)
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                cont.resume(returning: empty)
            }) as? ClipboardXPCProtocol else {
                cont.resume(returning: empty)
                return
            }
            proxy.listItems(query: query, pageToken: pageToken, limit: limit) { list in
                cont.resume(returning: list)
            }
        }
    }

    public func metasByIDs(ids: [String]) async -> ClipboardXPCList {
        await withCheckedContinuation { cont in
            let empty = ClipboardXPCList(items: [], nextPageToken: nil)
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                cont.resume(returning: empty)
            }) as? ClipboardXPCProtocol else {
                cont.resume(returning: empty)
                return
            }
            proxy.metasByIDs(ids: ids) { list in
                cont.resume(returning: list)
            }
        }
    }

    public func bodyText(forID id: String) async -> String? {
        await withCheckedContinuation { cont in
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                cont.resume(returning: nil)
            }) as? ClipboardXPCProtocol else {
                cont.resume(returning: nil)
                return
            }
            proxy.bodyText(forID: id) { body in
                cont.resume(returning: body)
            }
        }
    }

    public func bodyFileURLs(forID id: String) async -> [String]? {
        await withCheckedContinuation { cont in
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                cont.resume(returning: nil)
            }) as? ClipboardXPCProtocol else {
                cont.resume(returning: nil)
                return
            }
            proxy.bodyFileURLs(forID: id) { paths in
                cont.resume(returning: paths)
            }
        }
    }

    public func paste(itemID: String, plainText: Bool) async -> String {
        await withCheckedContinuation { cont in
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                cont.resume(returning: "manualPasteRequired")
            }) as? ClipboardXPCProtocol else {
                cont.resume(returning: "manualPasteRequired")
                return
            }
            proxy.paste(itemID: itemID, plainText: plainText) { result in
                cont.resume(returning: result)
            }
        }
    }

    public func pasteMany(itemIDs: [String], delimiter: String, plainText: Bool) async -> String {
        await withCheckedContinuation { cont in
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                cont.resume(returning: "manualPasteRequired")
            }) as? ClipboardXPCProtocol else {
                cont.resume(returning: "manualPasteRequired")
                return
            }
            proxy.pasteMany(itemIDs: itemIDs, delimiter: delimiter, plainText: plainText) { result in
                cont.resume(returning: result)
            }
        }
    }

    public func pasteText(text: String, plainText: Bool, saveAsNew: Bool) async -> String {
        await withCheckedContinuation { cont in
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                cont.resume(returning: "manualPasteRequired")
            }) as? ClipboardXPCProtocol else {
                cont.resume(returning: "manualPasteRequired")
                return
            }
            proxy.pasteText(text: text, plainText: plainText, saveAsNew: saveAsNew) { result in
                cont.resume(returning: result)
            }
        }
    }

    public func transformAndCopy(itemID: String, transform: String, saveAsNew: Bool) async -> String? {
        await withCheckedContinuation { cont in
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                cont.resume(returning: nil)
            }) as? ClipboardXPCProtocol else {
                cont.resume(returning: nil)
                return
            }
            proxy.transformAndCopy(itemID: itemID, transform: transform, saveAsNew: saveAsNew) { transformed in
                cont.resume(returning: transformed)
            }
        }
    }

    public func imageThumbnail(forID id: String, maxDim: Int) async -> Data? {
        await withCheckedContinuation { cont in
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                cont.resume(returning: nil)
            }) as? ClipboardXPCProtocol else {
                cont.resume(returning: nil)
                return
            }
            proxy.imageThumbnail(forID: id, maxDim: maxDim) { data in
                cont.resume(returning: data)
            }
        }
    }

    public func listSnippets() async -> [SnippetXPCDTO] {
        await withCheckedContinuation { cont in
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                cont.resume(returning: [])
            }) as? ClipboardXPCProtocol else {
                cont.resume(returning: [])
                return
            }
            proxy.listSnippets { snippets in
                cont.resume(returning: snippets)
            }
        }
    }
}
