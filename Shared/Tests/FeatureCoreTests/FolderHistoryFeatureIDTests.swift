@testable import FeatureCore
import XCTest

final class FolderHistoryFeatureIDTests: XCTestCase {
    func testFolderHistoryIDExists() {
        XCTAssertTrue(FeatureID.allCases.contains(.folderHistory))
    }
}
