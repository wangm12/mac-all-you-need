@testable import Platform
import XCTest

final class ChromiumCookiesTests: XCTestCase {
    func testDiscoveryReturnsArray() {
        let profiles = ChromiumCookies.discoverProfiles()
        XCTAssertTrue(profiles is [BrowserProfile])
    }
}
