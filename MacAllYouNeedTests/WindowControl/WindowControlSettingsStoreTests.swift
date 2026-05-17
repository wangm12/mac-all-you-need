import Core
@testable import MacAllYouNeed
import XCTest

final class WindowControlSettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "WindowControlSettingsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    func testLoadReturnsDefaultWhenUnset() {
        let settings = WindowControlSettingsStore.load(from: defaults)

        XCTAssertEqual(settings, .default)
    }

    func testSavesAndLoadsModifiedSettings() {
        var saved = WindowControlSettings.default
        saved.enabled = true
        saved.edgeSnapRequiresModifier = true
        saved.ignoredBundleIDs = ["com.apple.finder"]

        WindowControlSettingsStore.save(saved, to: defaults)
        let loaded = WindowControlSettingsStore.load(from: defaults)

        XCTAssertEqual(loaded, saved)
        XCTAssertTrue(loaded.enabled)
    }

    func testUsesExpectedDefaultsKey() {
        XCTAssertEqual(WindowControlSettingsStore.key, "windowControl.settings.v1")
    }

    func testInvalidPayloadFallsBackToDefault() {
        defaults.set(Data("not-json".utf8), forKey: WindowControlSettingsStore.key)

        let loaded = WindowControlSettingsStore.load(from: defaults)

        XCTAssertEqual(loaded, .default)
    }
}
