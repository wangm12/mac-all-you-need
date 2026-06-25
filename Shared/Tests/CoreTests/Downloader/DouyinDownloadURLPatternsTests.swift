import XCTest
@testable import Core

final class DouyinDownloadURLPatternsTests: XCTestCase {
    func testPrefersNativeResolveForPlayAPIURL() {
        let url = "https://www.douyin.com/aweme/v1/play/?file_id=abc&is_play_url=1"
        XCTAssertTrue(DouyinDownloadURLPatterns.prefersNativeResolve(url: url))
    }

    func testPrefersNativeResolveForVideoPage() {
        XCTAssertTrue(
            DouyinDownloadURLPatterns.prefersNativeResolve(
                url: "https://www.douyin.com/video/7653855010903641353"
            )
        )
    }

    func testDoesNotPreferNativeResolveForUnrelatedHost() {
        XCTAssertFalse(DouyinDownloadURLPatterns.prefersNativeResolve(url: "https://example.com/video/123"))
    }

    func testExtractAwemeIDFromExtensionTitle() {
        let title = "向佐 — 我的账号中邪了 — 7653855010903641353 — 1080p H.264"
        XCTAssertEqual(
            DouyinDownloadURLPatterns.extractAwemeIDFromTitle(title),
            "7653855010903641353"
        )
    }
}

final class DownloadEngineRouterDouyinTests: XCTestCase {
    func testPlayAPIWithMp4MediaTypeUsesDouyinDirect() {
        var record = DownloadRecord(
            url: "https://www.douyin.com/aweme/v1/play/?file_id=abc",
            title: "test",
            destinationPath: "/tmp/%(title)s.%(ext)s",
            state: .queued
        )
        record.mediaType = "mp4"
        XCTAssertEqual(DownloadEngineRouter.selectEngine(for: record), .douyinDirect)
    }

    func testVideoLabelDoesNotUseFfmpegDirect() {
        var record = DownloadRecord(
            url: "https://www.youtube.com/watch?v=iQyg-KypKAA",
            title: "test",
            destinationPath: "/tmp/%(title)s.%(ext)s",
            state: .queued
        )
        record.mediaType = "video"
        XCTAssertEqual(DownloadEngineRouter.selectEngine(for: record), .ytdlp)
    }

    func testAudioLabelDoesNotUseFfmpegDirect() {
        var record = DownloadRecord(
            url: "https://www.youtube.com/watch?v=iQyg-KypKAA",
            title: "test",
            destinationPath: "/tmp/%(title)s.%(ext)s",
            state: .queued
        )
        record.mediaType = "audio"
        XCTAssertEqual(DownloadEngineRouter.selectEngine(for: record), .ytdlp)
    }

    func testVideoPageWithMp4MediaTypeUsesDouyinDirect() {
        var record = DownloadRecord(
            url: "https://www.douyin.com/video/7653855010903641353",
            title: "test",
            destinationPath: "/tmp/%(title)s.%(ext)s",
            state: .queued
        )
        record.mediaType = "mp4"
        XCTAssertEqual(DownloadEngineRouter.selectEngine(for: record), .douyinDirect)
    }
}
