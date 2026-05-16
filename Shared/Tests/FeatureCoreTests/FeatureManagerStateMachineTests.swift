import XCTest
@testable import FeatureCore
@testable import Core

private func makeManager() -> FeatureManager {
    let downloader = FeatureDescriptor(
        id: .downloader, displayName: "Downloader", icon: "arrow.down",
        summary: "", detailDescription: "",
        assetPacks: [AssetPack(id: "downloader", bundledManifestKey: "downloader")],
        activator: NoopFeatureActivator()
    )
    let clipboard = FeatureDescriptor(
        id: .clipboard, displayName: "Clipboard", icon: "doc",
        summary: "", detailDescription: "",
        activator: NoopFeatureActivator()
    )
    let registry = FeatureRegistry(descriptors: [clipboard, downloader])
    let defaults = UserDefaults(suiteName: "FeatureManagerStateMachineTests-\(UUID().uuidString)")!
    return FeatureManager(registry: registry, defaults: defaults)
}

final class FeatureManagerStateMachineTests: XCTestCase {
    func testEnableSwiftOnlyFromDisabled() async throws {
        let mgr = makeManager()
        try await mgr.transition(.enable, for: .clipboard)
        let s = await mgr.state(for: .clipboard)
        XCTAssertEqual(s, .init(assetState: .notRequired, activationState: .enabled))
    }

    func testDisableSwiftOnlyFromEnabled() async throws {
        let mgr = makeManager()
        try await mgr.transition(.enable, for: .clipboard)
        try await mgr.transition(.disable, for: .clipboard)
        let s = await mgr.state(for: .clipboard)
        XCTAssertEqual(s, .init(assetState: .notRequired, activationState: .disabled))
    }

    func testCannotEnableWhileNotDownloaded() async {
        let mgr = makeManager()
        do {
            try await mgr.transition(.enable, for: .downloader)
            XCTFail("expected transition to throw")
        } catch let error as FeatureManager.TransitionError {
            XCTAssertEqual(error, .assetNotReady)
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testEnableAfterAssetBecomesPresent() async throws {
        let mgr = makeManager()
        try await mgr.setState(.init(assetState: .present(version: "1.0"), activationState: .disabled), for: .downloader)
        try await mgr.transition(.enable, for: .downloader)
        let s = await mgr.state(for: .downloader)
        XCTAssertEqual(s, .init(assetState: .present(version: "1.0"), activationState: .enabled))
    }

    func testDisableIsIdempotent() async throws {
        let mgr = makeManager()
        try await mgr.transition(.disable, for: .clipboard)
        try await mgr.transition(.disable, for: .clipboard)
        let s = await mgr.state(for: .clipboard)
        XCTAssertEqual(s.activationState, .disabled)
    }

    func testMarkAssetTransitions() async throws {
        let mgr = makeManager()
        try await mgr.markAssetState(.downloading(progress: 0.1), for: .downloader)
        let s1 = await mgr.state(for: .downloader)
        XCTAssertEqual(s1.assetState, .downloading(progress: 0.1))

        try await mgr.markAssetState(.present(version: "1.0"), for: .downloader)
        let s2 = await mgr.state(for: .downloader)
        XCTAssertEqual(s2.assetState, .present(version: "1.0"))

        try await mgr.markAssetState(.notDownloaded, for: .downloader)
        let final = await mgr.state(for: .downloader)
        XCTAssertEqual(final.assetState, .notDownloaded)
        XCTAssertEqual(final.activationState, .disabled, "asset removal must force-disable")
    }
}
