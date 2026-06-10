import XCTest
@testable import Core

final class DownloadBatchRateLimiterTests: XCTestCase {
    override func tearDown() {
        AppGroupSettings.defaults.removeObject(forKey: "downloadBatchSleepSeconds")
        super.tearDown()
    }

    func testDouyinAutoSleepWhenBatchLargeAndSettingZero() {
        AppGroupSettings.defaults.set(0, forKey: "downloadBatchSleepSeconds")
        XCTAssertEqual(
            DownloadBatchRateLimiter.effectiveSleepSeconds(kind: .douyinProfile, count: 50),
            0.25,
            accuracy: 0.001
        )
    }

    func testConfiguredSleepOverridesAuto() {
        AppGroupSettings.defaults.set(1.0, forKey: "downloadBatchSleepSeconds")
        XCTAssertEqual(
            DownloadBatchRateLimiter.effectiveSleepSeconds(kind: .douyinProfile, count: 100),
            1.0,
            accuracy: 0.001
        )
    }

    func testGentleSleepRequestsForPlaylistBatch() {
        XCTAssertEqual(
            DownloadBatchRateLimiter.gentleSleepRequestsArgs(kind: .playlist, batchCount: 12),
            ["--sleep-requests", "0.5"]
        )
        XCTAssertTrue(
            DownloadBatchRateLimiter.gentleSleepRequestsArgs(kind: .playlist, batchCount: 3).isEmpty
        )
    }
}
