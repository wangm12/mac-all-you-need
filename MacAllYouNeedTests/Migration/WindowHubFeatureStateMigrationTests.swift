import XCTest
import FeatureCore
@testable import MacAllYouNeed

final class WindowHubFeatureStateMigrationTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        let suiteName = "WindowHubFeatureStateMigrationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    func testMigratesEnabledFromLegacyDockPreviewsState() async throws {
        let registry = FeatureRegistryProvider.makeRegistry()
        let manager = FeatureManager(registry: registry, defaults: defaults)
        let dockState = FeatureRuntimeState(assetState: .notRequired, activationState: .enabled)
        let dockData = try JSONEncoder().encode(dockState)
        defaults.set(dockData, forKey: "feature.dockPreviews.runtimeState")

        try await WindowHubFeatureStateMigration.migrateIfNeeded(manager: manager)

        let hubState = await manager.state(for: .windowHub)
        XCTAssertEqual(hubState.activationState, .enabled)
        XCTAssertNil(defaults.data(forKey: "feature.dockPreviews.runtimeState"))
    }

    func testDefaultsToEnabledWhenNoLegacyState() async throws {
        let registry = FeatureRegistryProvider.makeRegistry()
        let manager = FeatureManager(registry: registry, defaults: defaults)

        try await WindowHubFeatureStateMigration.migrateIfNeeded(manager: manager)

        let hubState = await manager.state(for: .windowHub)
        XCTAssertEqual(hubState.activationState, .enabled)
    }

    func testSkipsWhenWindowHubStateAlreadyPersisted() async throws {
        let registry = FeatureRegistryProvider.makeRegistry()
        let manager = FeatureManager(registry: registry, defaults: defaults)
        let disabled = FeatureRuntimeState(assetState: .notRequired, activationState: .disabled)
        try await manager.setState(disabled, for: .windowHub)

        try await WindowHubFeatureStateMigration.migrateIfNeeded(manager: manager)

        let hubState = await manager.state(for: .windowHub)
        XCTAssertEqual(hubState.activationState, .disabled)
    }
}
