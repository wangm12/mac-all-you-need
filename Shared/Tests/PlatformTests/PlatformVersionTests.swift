@testable import Platform
import XCTest

final class PlatformVersionTests: XCTestCase {
    func testVersionFormat() {
        let value = PlatformVersion.value
        XCTAssertTrue(value.split(separator: ".").count == 3, "Version should be semver: \(value)")
    }
}
