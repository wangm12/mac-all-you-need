import XCTest
@testable import Core

final class DownloadBatchRateLimiterTests: XCTestCase {
    func testDouyinAutoSleepWhenBatchLarge() {
        XCTAssertEqual(
            DownloadBatchRateLimiter.effectiveSleepSeconds(kind: .douyinProfile, count: 50),
            1.0,
            accuracy: 0.001
        )
    }

    func testNoSleepForSmallDouyinBatch() {
        XCTAssertEqual(
            DownloadBatchRateLimiter.effectiveSleepSeconds(kind: .douyinProfile, count: 10),
            0,
            accuracy: 0.001
        )
    }

    func testGentleSleepRequestsForPlaylistBatch() {
        XCTAssertEqual(
            DownloadBatchRateLimiter.gentleSleepRequestsArgs(kind: .playlist, batchCount: 12),
            ["--sleep-requests", "0.5"]
        )
        // Threshold is now 3
        XCTAssertEqual(
            DownloadBatchRateLimiter.gentleSleepRequestsArgs(kind: .playlist, batchCount: 3),
            ["--sleep-requests", "0.5"]
        )
        XCTAssertTrue(
            DownloadBatchRateLimiter.gentleSleepRequestsArgs(kind: .playlist, batchCount: 2).isEmpty
        )
        // Douyin no longer produces sleep-requests here (handled by YtDlpArgumentBuilder)
        XCTAssertTrue(
            DownloadBatchRateLimiter.gentleSleepRequestsArgs(kind: .douyinProfile, batchCount: 50).isEmpty
        )
    }
}
