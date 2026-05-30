@testable import MacAllYouNeed
import XCTest

final class FileOrganizerDescriptorTests: XCTestCase {
    func testDescriptorHasCorrectFeatureID() {
        XCTAssertEqual(FileOrganizerDescriptor.descriptor().id, .aiFileOrganizer)
    }

    func testDescriptorMetadata() {
        let d = FileOrganizerDescriptor.descriptor()
        XCTAssertFalse(d.displayName.isEmpty)
        XCTAssertFalse(d.summary.isEmpty)
        XCTAssertTrue(d.requiredPermissions.contains(.fullDiskAccess))
    }
}
