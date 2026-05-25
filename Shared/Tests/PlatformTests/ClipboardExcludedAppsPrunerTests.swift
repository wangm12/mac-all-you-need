import Core
import Platform
import XCTest

final class ClipboardExcludedAppsPrunerTests: XCTestCase {
    func testPrunesBundleIDsNotInstalledOnDisk() {
        let suiteName = "ClipboardExcludedAppsPruner-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("expected suite defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            ["com.apple.finder", "com.fake.password.manager.xyzzy123"],
            forKey: "clipboardExcludedBundleIDs"
        )

        ClipboardExcludedAppsPruner.migrateIfNeeded(defaults: defaults)

        let result = defaults.stringArray(forKey: "clipboardExcludedBundleIDs") ?? []
        XCTAssertEqual(Set(result), ["com.apple.finder"])
        XCTAssertTrue(defaults.bool(forKey: "clipboardExcludedBundleIDs.prunedToInstalledApps.v1"))
    }

    func testMigrateRunsOnlyOnce() {
        let suiteName = "ClipboardExcludedAppsPruner-once-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("expected suite defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(["com.fake.app.notreal999"], forKey: "clipboardExcludedBundleIDs")
        ClipboardExcludedAppsPruner.migrateIfNeeded(defaults: defaults)
        XCTAssertEqual(defaults.stringArray(forKey: "clipboardExcludedBundleIDs"), [])

        defaults.set(["com.fake.app.notreal999"], forKey: "clipboardExcludedBundleIDs")
        ClipboardExcludedAppsPruner.migrateIfNeeded(defaults: defaults)
        XCTAssertEqual(
            defaults.stringArray(forKey: "clipboardExcludedBundleIDs"),
            ["com.fake.app.notreal999"],
            "second launch must not re-prune after the one-time migration flag is set"
        )
    }
}
