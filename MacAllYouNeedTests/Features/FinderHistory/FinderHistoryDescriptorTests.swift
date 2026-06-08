@testable import MacAllYouNeed
import FeatureCore
import XCTest

final class FinderHistoryDescriptorTests: XCTestCase {
    func testDescriptorID() {
        XCTAssertEqual(FinderHistoryDescriptor.descriptor().id, .folderHistory)
    }

    func testDescriptorIsDisabledByDefaultViaPermissions() {
        let d = FinderHistoryDescriptor.descriptor()
        XCTAssertTrue(d.requiredPermissions.contains(.accessibility))
        XCTAssertNotNil(d.settingsTabFactory)
        XCTAssertNotNil(d.menuBarItemFactory)
        XCTAssertNotNil(d.onboardingSetupFactory)
        if case .staticBundleExtension(let config) = d.osExtensionPolicy {
            XCTAssertEqual(config.extensionBundleID, "com.macallyouneed.app.finderhistory")
            XCTAssertTrue(config.respectsFeatureFlag)
        } else {
            XCTFail("Expected staticBundleExtension policy")
        }
    }
}
