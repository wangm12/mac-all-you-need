@testable import Core
import XCTest

final class FolderPreviewSettingsTests: XCTestCase {
    func testCascadeDefaultsToEnabledWhenUnset() {
        let suiteName = "folder-preview-settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(FolderPreviewSettings.cascadeEnabled(defaults: defaults))
    }

    func testCascadeReadsStoredPreference() {
        let suiteName = "folder-preview-settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: FolderPreviewSettings.cascadeKey)

        XCTAssertFalse(FolderPreviewSettings.cascadeEnabled(defaults: defaults))
    }
}
