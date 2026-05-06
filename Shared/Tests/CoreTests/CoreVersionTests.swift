@testable import Core
import XCTest

final class CoreVersionTests: XCTestCase {
    func testVersionFormat() {
        let value = CoreVersion.value
        XCTAssertTrue(value.split(separator: ".").count == 3, "Version should be semver: \(value)")
    }
}
