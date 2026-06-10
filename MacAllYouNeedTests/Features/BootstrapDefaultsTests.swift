import XCTest
import Core
import FeatureCore
@testable import MacAllYouNeed

final class BootstrapDefaultsTests: XCTestCase {
    func testSeedsAllFeaturesDisabledOnFirstLaunch() async throws {
        let suiteName = "BootstrapDefaultsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let registry = FeatureRegistryProvider.makeRegistry()
        let manager = FeatureManager(registry: registry, defaults: defaults)

        try await BootstrapDefaults.seedIfNeeded(manager: manager, defaults: defaults)

        for descriptor in registry.descriptors {
            let state = await manager.state(for: descriptor.id)
            XCTAssertEqual(
                state.activationState, .disabled,
                "first-launch should default \(descriptor.id) to disabled until explicitly enabled"
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

final class PriorUsageDetectorWindowControlTests: XCTestCase {
    func testDetectsEnabledWindowControlAsLayoutsAndGrabUsage() throws {
        let suiteName = "PriorUsageDetectorWindowControlTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var settings = WindowControlSettings.default
        settings.enabled = true
        settings.dragAnywhereEnabled = true
        WindowControlSettingsStore.save(settings, to: defaults)

        let detector = PriorUsageDetector(
            defaults: defaults,
            clipboardRecordCount: { 0 },
            downloadRecordCount: { 0 },
            folderPreviewLastInvoked: { nil }
        )

        let usage = try detector.detect()

        XCTAssertEqual(usage[.windowLayouts], .directEvidence)
        XCTAssertEqual(usage[.windowGrab], .directEvidence)
    }
}
