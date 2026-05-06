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
        guard let proxy = xpc.proxy() else { return }
        let trimmedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveQuery = trimmedQuery?.isEmpty == false ? trimmedQuery : nil
        if rememberQuery {
            activeQuery = effectiveQuery
        }
        let result: ClipboardXPCList = await withCheckedContinuation { cont in
            proxy.listItems(query: effectiveQuery, pageToken: nil, limit: limit) { list in cont.resume(returning: list) }
        }
        recentItems = result.items
    }
}
