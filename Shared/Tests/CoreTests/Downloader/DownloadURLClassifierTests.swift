@testable import Core
import XCTest

final class DownloadURLClassifierTests: XCTestCase {
    func testPlaylistURLDetection() {
        XCTAssertTrue(DownloadURLClassifier.isPlaylistURL("https://www.youtube.com/playlist?list=PL123"))
        XCTAssertTrue(DownloadURLClassifier.isPlaylistURL("https://www.youtube.com/@creator/videos"))
    }

    func testBilibiliSpaceDetection() {
        XCTAssertTrue(DownloadURLClassifier.isBilibiliSpaceURL("https://space.bilibili.com/123"))
    }

    func testDouyinProfileDetection() {
        XCTAssertTrue(DownloadURLClassifier.isDouyinProfileHomeURL("https://www.douyin.com/user/MS4wLjABAAAAabc"))
    }

    func testRouteCollectionURL() {
        let route = DownloadURLClassifier.route(for: "https://www.youtube.com/playlist?list=PL123")
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
