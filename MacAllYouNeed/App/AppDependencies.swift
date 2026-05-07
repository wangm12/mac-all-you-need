import Core
import Foundation
import SwiftUI

@MainActor
@Observable
final class AppDependencies: NSObject, ClipboardXPCClientCallback {
    let xpc: ClipboardXPCClient
    var recentItems: [ClipboardXPCMeta] = []
    private var activeQuery: String?

    override init() {
        xpc = ClipboardXPCClient(resumesImmediately: false)
        super.init()
        xpc.connection.exportedInterface = NSXPCInterface(with: ClipboardXPCClientCallback.self)
        xpc.connection.exportedObject = self
        xpc.resume()
        xpc.proxy()?.registerCallback { _ in }
    }

    nonisolated func itemsInvalidated() {
        Task { @MainActor in await self.refresh(query: self.activeQuery) }
    }

    func refreshUsingRememberedQuery(limit: Int = 50) async {
        await refresh(query: activeQuery, limit: limit)
    }

    func clearRememberedQuery() {
        activeQuery = nil
    }

    func refresh(query: String? = nil, limit: Int = 50, rememberQuery: Bool = false) async {
        let trimmedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveQuery = trimmedQuery?.isEmpty == false ? trimmedQuery : nil
        if rememberQuery {
            activeQuery = effectiveQuery
        }
        let empty = ClipboardXPCList(items: [], nextPageToken: nil)
        let result: ClipboardXPCList = await withCheckedContinuation { cont in
            // Use an error-handling proxy so the continuation always resumes even
            // if the XPC connection drops before the callback fires (e.g. daemon
            // not yet ready when the app first connects).
            let proxy = xpc.connection.remoteObjectProxyWithErrorHandler { _ in
                cont.resume(returning: empty)
            } as? ClipboardXPCProtocol
            guard let proxy else { cont.resume(returning: empty); return }
            proxy.listItems(query: effectiveQuery, pageToken: nil, limit: limit) { list in
                cont.resume(returning: list)
            }
        }
        recentItems = result.items
    }
}
