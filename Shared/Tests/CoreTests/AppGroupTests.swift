@testable import Core
import XCTest

final class AppGroupTests: XCTestCase {
    func testIdentifierIsConstant() {
        XCTAssertEqual(AppGroup.identifier, "group.com.macallyouneed.shared")
    }

    func testContainerURLOverridable() {
        let original = AppGroup.containerURLOverride
        defer { AppGroup.containerURLOverride = original }

        let tmp = URL(fileURLWithPath: "/tmp/mayn-test")
        AppGroup.containerURLOverride = tmp
        XCTAssertEqual(AppGroup.containerURL(), tmp)
        XCTAssertFalse(AppGroup.isUsingFallbackContainer())
    }

    func testContainerURLOverridableByEnvironment() {
        let original = AppGroup.containerURLOverride
        defer { AppGroup.containerURLOverride = original }
        AppGroup.containerURLOverride = nil

        let tmp = URL(fileURLWithPath: "/tmp/mayn-env-test", isDirectory: true)
        let url = AppGroup.containerURL(environment: [
            AppGroup.containerOverrideEnvironmentKey: tmp.path
        ])

        XCTAssertEqual(url, tmp)
    }

    func testSettingsUseIsolatedSuiteWhenContainerIsOverriddenByEnvironment() {
        let key = "appGroupOverride-\(UUID().uuidString)"
        let defaults = AppGroupSettings.defaults(for: [
            AppGroup.containerOverrideEnvironmentKey: "/tmp/mayn-env-test"
        ])

        defaults.set("isolated", forKey: key)

        XCTAssertFalse(defaults === UserDefaults.standard)
        XCTAssertNil(UserDefaults.standard.string(forKey: key))
        XCTAssertEqual(defaults.string(forKey: key), "isolated")
    }

    func testSettingsSuiteCanBeOverriddenForAuditMode() {
        let suiteName = "UIAuditDefaults-\(UUID().uuidString)"
        let defaults = AppGroupSettings.defaults(for: [
            AppGroupSettings.defaultsSuiteOverrideEnvironmentKey: suiteName
        ])
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("audit", forKey: "source")

        XCTAssertFalse(defaults === UserDefaults.standard)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "source"), nil)
        XCTAssertEqual(UserDefaults(suiteName: suiteName)?.string(forKey: "source"), "audit")
    }

    func testContainerURLIsAlwaysValid() {
        // On macOS, containerURL(forSecurityApplicationGroupIdentifier:) creates the
        // group container directory and returns it for any valid identifier, regardless
        // of entitlement — unlike iOS. So containerURL() always returns a usable path.
        let url = AppGroup.containerURL()
        XCTAssertFalse(url.path.isEmpty)
    }
}
