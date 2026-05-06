import XCTest
@testable import UI

final class UIVersionTests: XCTestCase {
    func testVersionFormat() {
        let value = UIVersion.value
        XCTAssertTrue(value.split(separator: ".").count == 3, "Version should be semver: \(value)")
    }
}
