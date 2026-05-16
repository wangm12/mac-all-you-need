import XCTest
import FeatureCore
@testable import MacAllYouNeed

final class BootstrapDefaultsTests: XCTestCase {
    func testSeedsAllFeaturesEnabledOnFirstLaunch() async throws {
        let suiteName = "BootstrapDefaultsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let registry = FeatureRegistryProvider.makeRegistry()
        let manager = FeatureManager(registry: registry, defaults: defaults)

        try await BootstrapDefaults.seedIfNeeded(manager: manager, defaults: defaults)

        for descriptor in registry.descriptors {
            let state = await manager.state(for: descriptor.id)
            XCTAssertEqual(
                state.activationState, .enabled,
                "first-launch must default \(descriptor.id) to enabled for backward compat"
            )
        }
        XCTAssertTrue(defaults.bool(forKey: BootstrapDefaults.seededKey))
    }

    func testIsIdempotent() async throws {
        let suiteName = "BootstrapDefaultsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let registry = FeatureRegistryProvider.makeRegistry()
        let manager = FeatureManager(registry: registry, defaults: defaults)

        try await BootstrapDefaults.seedIfNeeded(manager: manager, defaults: defaults)
        // Simulate user disabling clipboard after first launch
        try await manager.transition(.disable, for: .clipboard)
        // Second seed must not undo the user's change
        try await BootstrapDefaults.seedIfNeeded(manager: manager, defaults: defaults)

        let state = await manager.state(for: .clipboard)
        XCTAssertEqual(state.activationState, .disabled, "second seed must not undo user changes")
    }
}
