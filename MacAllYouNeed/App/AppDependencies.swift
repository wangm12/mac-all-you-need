import Core
import Foundation
import SwiftUI

@MainActor
@Observable
final class AppDependencies: NSObject, ClipboardXPCClientCallback {
    let xpc: ClipboardXPCClient
    var recentItems: [ClipboardXPCMeta] = []

    override init() {
        xpc = ClipboardXPCClient()
        super.init()
        xpc.connection.exportedInterface = NSXPCInterface(with: ClipboardXPCClientCallback.self)
        xpc.connection.exportedObject = self
        xpc.proxy()?.registerCallback { _ in }
    }

    nonisolated func itemsInvalidated() {
        Task { @MainActor in await self.refresh() }
    }

    func refresh(limit: Int = 50) async {
        guard let proxy = xpc.proxy() else { return }
        let result: ClipboardXPCList = await withCheckedContinuation { cont in
            proxy.listItems(query: nil, pageToken: nil, limit: limit) { list in cont.resume(returning: list) }
        }
        recentItems = result.items
    }
}
