@testable import MacAllYouNeed
import XCTest

final class DownloadCoordinatorCookieModeTests: XCTestCase {
    func testDispatchBlockPolicyDoesNotBlockOutsideExtensionOnlyMode() {
        XCTAssertFalse(
            DownloadCoordinator.dispatchShouldBlockForMissingExtensionCookies(
                url: "https://www.youtube.com/watch?v=aqz-KE-bpKQ",
                cookieMode: "browser_auto",
                hasExtensionCookieFile: false
            )
        )
    }

    func testDispatchBlockPolicyBlocksAuthHostsWithoutSyncedCompanionCookies() {
        XCTAssertTrue(
            DownloadCoordinator.dispatchShouldBlockForMissingExtensionCookies(
                url: "https://www.youtube.com/watch?v=aqz-KE-bpKQ",
                cookieMode: "extension_only",
                hasExtensionCookieFile: false
            )
        )
        XCTAssertTrue(
            DownloadCoordinator.dispatchShouldBlockForMissingExtensionCookies(
                url: "https://www.douyin.com/user/MS4wLjABAAAAabc",
                cookieMode: "extension_only",
                hasExtensionCookieFile: false
            )
        )
    }

    func testDispatchBlockPolicyAllowsAuthHostsWhenSyncedCompanionCookiesExist() {
        XCTAssertFalse(
            DownloadCoordinator.dispatchShouldBlockForMissingExtensionCookies(
                url: "https://www.instagram.com/p/abc123",
                cookieMode: "extension_only",
                hasExtensionCookieFile: true
            )
        )
    }

    func testDispatchBlockPolicyIgnoresNonAuthHosts() {
        XCTAssertFalse(
            DownloadCoordinator.dispatchShouldBlockForMissingExtensionCookies(
                url: "https://example.com/video",
                cookieMode: "extension_only",
                hasExtensionCookieFile: false
            )
        )
    }
}
