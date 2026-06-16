import XCTest
@testable import Core

final class YtDlpArgumentBuilderTests: XCTestCase {
    func testBuildIncludesDouyinHeadersAndReferer() {
        var record = DownloadRecord(
            url: "https://www.douyin.com/video/123",
            title: "test",
            destinationPath: "/tmp/out.mp4",
            state: .queued
        )
        record.referer = "https://example.com"
        record.customHeaders = ["User-Agent": "UA", "X-Test": "v"]

        let args = YtDlpArgumentBuilder.build(
            record: record,
            cookies: ["--cookies", "/tmp/c.txt"],
            formatArgs: ["-f", "best"],
            batchArgs: ["--sleep-interval-requests", "0.25"],
            options: YtDlpArgumentOptions(
                concurrentFragments: 8,
                sleepInterval: 1,
                speedMode: .gentle
            )
        )

        XCTAssertTrue(args.contains("--cookies"))
        XCTAssertTrue(args.contains("--concurrent-fragments"))
        // Douyin caps concurrent-fragments at 2 regardless of user setting
        XCTAssertTrue(args.contains("2"))
        XCTAssertFalse(args.contains("8"))
        XCTAssertTrue(args.contains("--retry-sleep"))
        XCTAssertTrue(args.contains("fragment:linear=2::5"))
        XCTAssertTrue(args.contains("--referer"))
        XCTAssertTrue(args.contains("https://www.douyin.com/"))
        XCTAssertTrue(args.contains("https://example.com"))
        XCTAssertTrue(args.contains("Origin:https://www.douyin.com"))
        XCTAssertTrue(args.contains("Accept-Language:zh-CN,zh;q=0.9,en-US;q=0.8"))
        XCTAssertTrue(args.contains("--sleep-requests"))
        XCTAssertTrue(args.contains("--sleep-interval"))
        XCTAssertTrue(args.contains("User-Agent:UA"))
        XCTAssertTrue(args.contains("X-Test:v"))
    }

    func testBuildIncludesNativePlaylist() {
        var record = DownloadRecord(
            url: "https://www.youtube.com/watch?v=abc",
            title: "test",
            destinationPath: "/tmp/out.mp4",
            state: .queued
        )
        record.nativeYoutubePlaylist = true

        let args = YtDlpArgumentBuilder.build(
            record: record,
            cookies: [],
            formatArgs: [],
            batchArgs: [],
            options: YtDlpArgumentOptions(
                concurrentFragments: 3,
                sleepInterval: 0,
                speedMode: .turbo
            )
        )

        XCTAssertTrue(args.contains("--yes-playlist"))
        XCTAssertFalse(args.contains("--downloader"))
        XCTAssertTrue(args.contains("--retry-sleep"))
        XCTAssertTrue(args.contains("fragment:linear=0.2::1.5"))
        // Non-Douyin URL uses the configured fragments count unchanged
        XCTAssertTrue(args.contains("3"))
    }

    func testDouyinConcurrentFragmentsCappedAtTwo() {
        let record = DownloadRecord(
            url: "https://www.douyin.com/video/999",
            title: "t",
            destinationPath: "/tmp/out.mp4",
            state: .queued
        )
        let args = YtDlpArgumentBuilder.build(
            record: record,
            cookies: [],
            formatArgs: [],
            batchArgs: [],
            options: YtDlpArgumentOptions(concurrentFragments: 8)
        )
        let idx = args.firstIndex(of: "--concurrent-fragments")
        XCTAssertNotNil(idx)
        if let idx {
            XCTAssertEqual(args[args.index(after: idx)], "2")
        }
    }

    func testDouyinAlwaysHasSleepAndAcceptLanguage() {
        let record = DownloadRecord(
            url: "https://www.douyin.com/video/42",
            title: "t",
            destinationPath: "/tmp/out.mp4",
            state: .queued
        )
        let args = YtDlpArgumentBuilder.build(
            record: record,
            cookies: [],
            formatArgs: [],
            batchArgs: [],
            options: YtDlpArgumentOptions()
        )
        XCTAssertTrue(args.contains("--sleep-requests"))
        XCTAssertTrue(args.contains("--sleep-interval"))
        XCTAssertTrue(args.contains("Accept-Language:zh-CN,zh;q=0.9,en-US;q=0.8"))
    }

    func testNonDouyinDoesNotGetDouyinHeaders() {
        let record = DownloadRecord(
            url: "https://www.youtube.com/watch?v=xyz",
            title: "t",
            destinationPath: "/tmp/out.mp4",
            state: .queued
        )
        let args = YtDlpArgumentBuilder.build(
            record: record,
            cookies: [],
            formatArgs: [],
            batchArgs: [],
            options: YtDlpArgumentOptions(concurrentFragments: 4)
        )
        XCTAssertFalse(args.contains("Origin:https://www.douyin.com"))
        XCTAssertFalse(args.contains("Accept-Language:zh-CN,zh;q=0.9,en-US;q=0.8"))
        // Uses user's configured fragments, not capped
        let idx = args.firstIndex(of: "--concurrent-fragments")
        XCTAssertNotNil(idx)
        if let idx { XCTAssertEqual(args[args.index(after: idx)], "4") }
    }
}
