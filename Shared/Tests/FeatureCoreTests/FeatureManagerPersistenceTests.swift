import XCTest
import SwiftUI
@testable import FeatureCore
@testable import Core

private func makeRegistry() -> FeatureRegistry {
    let clipboard = FeatureDescriptor(
        id: .clipboard, displayName: "Clipboard", icon: "doc",
        summary: "", detailDescription: "",
        activator: NoopFeatureActivator()
    )
    let downloader = FeatureDescriptor(
        id: .downloader, displayName: "Downloader", icon: "arrow.down",
        summary: "", detailDescription: "",
        assetPacks: [AssetPack(id: "downloader", bundledManifestKey: "downloader")],
        activator: NoopFeatureActivator()
    )
    return FeatureRegistry(descriptors: [clipboard, downloader])
}

final class FeatureManagerPersistenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "FeatureManagerPersistenceTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testReturnsInitialDefaultWhenUnset() async {
        let manager = FeatureManager(registry: makeRegistry(), defaults: defaults)
        let clipboard = await manager.state(for: .clipboard)
        let downloader = await manager.state(for: .downloader)
        XCTAssertEqual(clipboard, .init(assetState: .notRequired, activationState: .disabled))
        XCTAssertEqual(downloader, .init(assetState: .notDownloaded, activationState: .disabled))
    }

    func testPersistsAcrossInstances() async throws {
        let mgr1 = FeatureManager(registry: makeRegistry(), defaults: defaults)
        try await mgr1.setState(.init(assetState: .notRequired, activationState: .enabled), for: .clipboard)

        let mgr2 = FeatureManager(registry: makeRegistry(), defaults: defaults)
        let read = await mgr2.state(for: .clipboard)
        XCTAssertEqual(read, .init(assetState: .notRequired, activationState: .enabled))
    }

    func testStateWriteIsIsolatedPerFeature() async throws {
        let manager = FeatureManager(registry: makeRegistry(), defaults: defaults)
        try await manager.setState(.init(assetState: .notRequired, activationState: .enabled), for: .clipboard)
        let downloader = await manager.state(for: .downloader)
        XCTAssertEqual(downloader, .init(assetState: .notDownloaded, activationState: .disabled),
                       "Writing one feature must not affect another")
    }
}
