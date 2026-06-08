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
    let fileThumbnailLoader: FileThumbnailLoader
    let pinboardStore: PinboardStore
    let snippetStore: SnippetStore
    /// Exposed so non-dock readers (the menu bar popover) can copy a card's
    /// content to NSPasteboard via the same `restoreToPasteboard` path the
    /// dock uses — handles RTF/HTML/image/file URLs, not just plain text.
    let clip: ClipboardStore
    let blobs: BlobStore
    let search: SearchStore
    let clipboardWorker: ClipboardWorker
    let dockModel: ClipboardDockModel

    /// Pinboards, snippets, the clipboard store, and the blob store are all
    /// constructed by AppController against the keychain-backed device key;
    /// injected here so that a missing/locked keychain surfaces as
    /// AppController.init throwing instead of silently building temporary
    /// stores with a throwaway key. The clip store is also shared with
    /// LocalClipboardReader and the dock model so all read paths hit one
    /// DatabaseQueue. Image and file loaders take clip + blobs so cards
    /// render thumbnails / file names without a working XPC connection.
    init(
        pinboards: PinboardStore,
        snippets: SnippetStore,
        clip: ClipboardStore,
        blobs: BlobStore,
        search: SearchStore,
        clipboardWorker: ClipboardWorker
    ) {
        let client = ClipboardXPCClient(resumesImmediately: false)
        xpc = client

        let imageLoader = ImageBlobLoader(xpc: client, clip: clip, blobs: blobs)
        let fileLoader = FileURLLoader(xpc: client, clip: clip)
        let fileThumbnailLoader = FileThumbnailLoader()
        self.imageLoader = imageLoader
        self.fileLoader = fileLoader
        self.fileThumbnailLoader = fileThumbnailLoader

        pinboardStore = pinboards
        snippetStore = snippets
        self.clip = clip
        self.blobs = blobs
        self.search = search
        self.clipboardWorker = clipboardWorker

        dockModel = ClipboardDockModel(
            xpc: client,
            appIcons: appIcons,
            imageLoader: imageLoader,
            fileLoader: fileLoader,
            fileThumbnailLoader: fileThumbnailLoader,
            pinboards: pinboards,
            snippets: snippets,
            clip: clip,
            blobs: blobs,
            searchStore: search,
            clipboardWorker: clipboardWorker
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
