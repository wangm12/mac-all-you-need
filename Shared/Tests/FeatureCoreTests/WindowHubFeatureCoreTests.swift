import XCTest
@testable import FeatureCore

final class WindowHubFeatureCoreTests: XCTestCase {
    func testWindowHubFeatureIDExists() {
        XCTAssertTrue(FeatureID.allCases.contains(.windowHub))
    }

    func testWindowHubRawValueIsStable() {
        XCTAssertEqual(FeatureID.windowHub.rawValue, "windowHub")
    }
}
