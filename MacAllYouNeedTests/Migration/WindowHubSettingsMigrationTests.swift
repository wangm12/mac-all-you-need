import XCTest
@testable import MacAllYouNeed

final class WindowHubSettingsMigrationTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        let suiteName = "WindowHubSettingsMigrationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    func testMigratesLegacyDisabledBrowserTabDiscoveryToEnabled() {
        var settings = WindowHubSettings()
        settings.browserTabDiscoveryEnabled = false
        WindowHubSettingsStore.save(settings, to: defaults)

        WindowHubSettingsMigration.migrateIfNeeded(defaults: defaults)

        let migrated = WindowHubSettingsStore.load(from: defaults)
        XCTAssertTrue(migrated.browserTabDiscoveryEnabled)
    }

    func testDoesNotOverwriteAlreadyEnabledBrowserTabDiscovery() {
        var settings = WindowHubSettings()
        settings.browserTabDiscoveryEnabled = true
        WindowHubSettingsStore.save(settings, to: defaults)

        WindowHubSettingsMigration.migrateIfNeeded(defaults: defaults)

        let migrated = WindowHubSettingsStore.load(from: defaults)
        XCTAssertTrue(migrated.browserTabDiscoveryEnabled)
    }
}
