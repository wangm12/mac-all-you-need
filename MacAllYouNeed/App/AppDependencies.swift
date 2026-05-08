import Core
import CryptoKit
import Foundation
import Platform
import SwiftUI

@MainActor
@Observable
final class AppDependencies: NSObject, ClipboardXPCClientCallback {
    let xpc: ClipboardXPCClient
    let appIcons = AppIconResolver()
    let imageLoader: ImageBlobLoader
    let fileLoader: FileURLLoader
    let pinboardStore: PinboardStore
    let snippetStore: SnippetStore
    let dockModel: ClipboardDockModel

    /// Pinboards are constructed by AppController against the keychain-backed
    /// device key; injected here so that a missing/locked keychain surfaces as
    /// AppController.init throwing instead of silently building a temporary
    /// store with a throwaway key (which orphaned user data on next launch).
    init(pinboards: PinboardStore) {
        let client = ClipboardXPCClient(resumesImmediately: false)
        xpc = client

        let imageLoader = ImageBlobLoader(xpc: client)
        let fileLoader = FileURLLoader(xpc: client)
        self.imageLoader = imageLoader
        self.fileLoader = fileLoader

        pinboardStore = pinboards

        let key = try? KeyManager(keychain: SystemKeychain()).deviceKey()
        let snippetDB = try? Database(
            url: AppGroup.containerURL().appendingPathComponent("databases/snippets.sqlite"),
            migrations: SnippetStore.migrations
        )
        let snippets: SnippetStore = {
            if let key, let snippetDB {
                return SnippetStore(database: snippetDB, deviceKey: key)
            }
            let fallbackDB = try! Database(
                url: FileManager.default.temporaryDirectory.appendingPathComponent("snip-\(UUID().uuidString).sqlite"),
                migrations: SnippetStore.migrations
            )
            return SnippetStore(database: fallbackDB, deviceKey: SymmetricKey(size: .bits256))
        }()
        snippetStore = snippets

        dockModel = ClipboardDockModel(
            xpc: client,
            appIcons: appIcons,
            imageLoader: imageLoader,
            fileLoader: fileLoader,
            pinboards: pinboards,
            snippets: snippets
        )

        super.init()

        xpc.connection.exportedInterface = NSXPCInterface(with: ClipboardXPCClientCallback.self)
        xpc.connection.exportedObject = self
        xpc.resume()
        xpc.proxy()?.registerCallback { _ in }

        Task { @MainActor in
            for delay in [0.5, 1.0, 2.0, 4.0] {
                await dockModel.refresh()
                if !dockModel.items.isEmpty { return }
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    nonisolated func itemsInvalidated() {
        Task { @MainActor in dockModel.refreshDebounced() }
    }
}
