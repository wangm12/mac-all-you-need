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
    let dockModel: ClipboardDockModel

    override init() {
        let client = ClipboardXPCClient(resumesImmediately: false)
        xpc = client

        let imageLoader = ImageBlobLoader(xpc: client)
        let fileLoader = FileURLLoader(xpc: client)
        self.imageLoader = imageLoader
        self.fileLoader = fileLoader

        let key = try? KeyManager(keychain: SystemKeychain()).deviceKey()
        let pinboardDB = try? Database(
            url: AppGroup.containerURL().appendingPathComponent("databases/pinboards.sqlite"),
            migrations: PinboardStore.migrations
        )
        let pinboards: PinboardStore = {
            if let key, let pinboardDB {
                return PinboardStore(database: pinboardDB, deviceKey: key)
            }
            let fallbackDB = try! Database(
                url: FileManager.default.temporaryDirectory.appendingPathComponent("pinboards-\(UUID().uuidString).sqlite"),
                migrations: PinboardStore.migrations
            )
            return PinboardStore(database: fallbackDB, deviceKey: SymmetricKey(size: .bits256))
        }()
        pinboardStore = pinboards

        dockModel = ClipboardDockModel(
            xpc: client,
            appIcons: appIcons,
            imageLoader: imageLoader,
            fileLoader: fileLoader,
            pinboards: pinboards
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
