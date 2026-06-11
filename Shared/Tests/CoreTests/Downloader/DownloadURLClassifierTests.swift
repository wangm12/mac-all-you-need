@testable import Core
import XCTest

final class DownloadURLClassifierTests: XCTestCase {
    func testPlaylistURLDetection() {
        XCTAssertTrue(DownloadURLClassifier.isPlaylistURL("https://www.youtube.com/playlist?list=PL123"))
        XCTAssertTrue(DownloadURLClassifier.isPlaylistURL("https://www.youtube.com/@creator/videos"))
        XCTAssertTrue(DownloadURLClassifier.isPlaylistURL("https://www.youtube.com/channel/UC1234567890/videos"))
        XCTAssertTrue(DownloadURLClassifier.isPlaylistURL("https://www.youtube.com/user/google/videos"))
    }

    func testSingleWatchURLDoesNotOpenCollectionPicker() {
        XCTAssertFalse(DownloadURLClassifier.shouldOpenCollectionPicker("https://www.youtube.com/watch?v=aqz-KE-bpKQ"))
        XCTAssertEqual(DownloadURLClassifier.route(for: "https://www.youtube.com/watch?v=aqz-KE-bpKQ"), .single("https://www.youtube.com/watch?v=aqz-KE-bpKQ"))
    }

    func testDownloadablePasteboardURLDetectsBulkAndProfileLinks() {
        XCTAssertTrue(DownloadURLClassifier.isDownloadablePasteboardURL("https://www.youtube.com/@OpenAI/videos"))
        XCTAssertTrue(DownloadURLClassifier.isDownloadablePasteboardURL("https://www.douyin.com/user/MS4wLjABAAAAabc?from_tab_name=main"))
    }

    func testDownloadablePasteboardURLIgnoresSingleWatchLinks() {
        XCTAssertFalse(DownloadURLClassifier.isDownloadablePasteboardURL("https://www.youtube.com/watch?v=aqz-KE-bpKQ"))
    }

    func testFirstDownloadableURLFindsDouyinProfileWithQueryParamsInProse() {
        let text = "Please download this: https://www.douyin.com/user/MS4wLjABAAAAabc?from_tab_name=main&vid=123"
        let url = DownloadURLClassifier.firstDownloadableURL(in: text)
        XCTAssertEqual(url, "https://www.douyin.com/user/MS4wLjABAAAAabc?from_tab_name=main&vid=123")
    }

    func testBilibiliSpaceDetection() {
        XCTAssertTrue(DownloadURLClassifier.isBilibiliSpaceURL("https://space.bilibili.com/123"))
    }

    func testDouyinProfileDetection() {
        XCTAssertTrue(DownloadURLClassifier.isDouyinProfileHomeURL("https://www.douyin.com/user/MS4wLjABAAAAabc"))
    }

    func testDouyinProfileDetectionWithQueryParams() {
        let url = "https://www.douyin.com/user/MS4wLjABAAAAH7bR1jsG3QEo46LvfvW3J8ILrCbJN1qGKXgwRorKaGmhouCHp5e0ADIOclAJ4V-v?from_tab_name=main&vid=7648544231288699385"
        XCTAssertTrue(DownloadURLClassifier.isDouyinProfileHomeURL(url))
        let route = DownloadURLClassifier.route(for: url)
        guard case .douyinProfile = route else {
            return XCTFail("expected douyinProfile route")
        }
    }

    func testRouteCollectionURL() {
        let route = DownloadURLClassifier.route(for: "https://www.youtube.com/playlist?list=PL123")
        guard case .collection = route else {
            return XCTFail("expected collection route")
        }
    }

    func testRouteYouTubeChannelURLAsCollection() {
        let route = DownloadURLClassifier.route(for: "https://www.youtube.com/@OpenAI/videos")
        guard case .collection = route else {
            return XCTFail("expected collection route")
        }
    }

    func testSplitMultiURL() {
        let lines = DownloadURLClassifier.splitMultiURL("https://a.test\n\nhttps://b.test")
        XCTAssertEqual(lines.count, 2)
    }

    func testFirstDownloadableURLFindsPlaylist() {
        let url = DownloadURLClassifier.firstDownloadableURL(
            in: "https://www.youtube.com/playlist?list=PL123"
        )
        XCTAssertEqual(url, "https://www.youtube.com/playlist?list=PL123")
    }

    func testFirstDownloadableURLFindsBilibiliSpace() {
        let url = DownloadURLClassifier.firstDownloadableURL(in: "https://space.bilibili.com/123456")
        XCTAssertEqual(url, "https://space.bilibili.com/123456")
    }
}
