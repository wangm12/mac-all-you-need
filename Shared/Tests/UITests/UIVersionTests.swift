@testable import UI
import XCTest

final class UIVersionTests: XCTestCase {
    func testVersionFormat() {
        let value = UIVersion.value
        XCTAssertTrue(value.split(separator: ".").count == 3, "Version should be semver: \(value)")
    }
}
