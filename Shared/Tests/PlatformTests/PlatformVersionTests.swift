import XCTest
@testable import Platform

final class PlatformVersionTests: XCTestCase {
    func testVersionFormat() {
        let value = PlatformVersion.value
        XCTAssertTrue(value.split(separator: ".").count == 3, "Version should be semver: \(value)")
    }
}
