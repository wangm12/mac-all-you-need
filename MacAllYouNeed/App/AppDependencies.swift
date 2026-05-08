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

    /// Pinboards and snippets are constructed by AppController against the
    /// keychain-backed device key; injected here so that a missing/locked
    /// keychain surfaces as AppController.init throwing instead of silently
    /// building temporary stores with a throwaway key (which orphaned user
    /// data on next launch). Snippet injection also ensures only one
    /// SnippetStore opens snippets.sqlite per process — a second
    /// DatabaseQueue on the same file races with the SnippetExpander.
    init(pinboards: PinboardStore, snippets: SnippetStore) {
        let client = ClipboardXPCClient(resumesImmediately: false)
        xpc = client

        let imageLoader = ImageBlobLoader(xpc: client)
        let fileLoader = FileURLLoader(xpc: client)
        self.imageLoader = imageLoader
        self.fileLoader = fileLoader

        pinboardStore = pinboards
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
