import XCTest
import FeatureCore
@testable import MacAllYouNeed

final class FeatureRuntimeTests: XCTestCase {
    private func makeRuntime() async throws -> (FeatureRuntime, FeatureManager) {
        let suiteName = "FeatureRuntimeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let registry = FeatureRegistryProvider.makeRegistry()
        let manager = FeatureManager(registry: registry, defaults: defaults)
        try await BootstrapDefaults.seedIfNeeded(manager: manager, defaults: defaults)
        let runtime = FeatureRuntime(registry: registry, manager: manager)
        return (runtime, manager)
    }

    func testActivatesEnabledFeaturesOnBoot() async throws {
        let (runtime, manager) = try await makeRuntime()
        let registry = await runtime.registry
        for descriptor in registry.descriptors {
            try await manager.transition(.enable, for: descriptor.id)
        }
        await runtime.activateAllEnabled()
        for descriptor in registry.descriptors {
            let isActive = await runtime.isActive(descriptor.id)
            XCTAssertTrue(isActive, "\(descriptor.id) should be active after boot")
        }
    }

    func testSkipsDisabledFeatures() async throws {
        let (runtime, manager) = try await makeRuntime()
        try await manager.transition(.disable, for: .clipboard)
        await runtime.activateAllEnabled()

        let clipboardActive = await runtime.isActive(.clipboard)
        XCTAssertFalse(clipboardActive)
        try await manager.transition(.enable, for: .voice)
        await runtime.activateAllEnabled()
        let voiceActive = await runtime.isActive(.voice)
        XCTAssertTrue(voiceActive)
    }

    func testDeactivateOne() async throws {
        let (runtime, manager) = try await makeRuntime()
        await runtime.activateAllEnabled()
        try await runtime.applyTransition(.disable, for: .voice)

        let voiceActive = await runtime.isActive(.voice)
        XCTAssertFalse(voiceActive)
        let state = await manager.state(for: .voice)
        XCTAssertEqual(state.activationState, .disabled)
    }
}
