@testable import Platform
import XCTest

final class URLDetectorTests: XCTestCase {
    func testYouTubeWatch() {
        let url = URLDetector.videoBearingURL(in: "https://www.youtube.com/watch?v=abc")
        XCTAssertEqual(url?.host, "www.youtube.com")
    }

    func testNonVideoURLReturnsNil() {
        XCTAssertNil(URLDetector.videoBearingURL(in: "https://example.com/article"))
    }

    func testInlineURL() {
        let url = URLDetector.videoBearingURL(in: "check this https://vimeo.com/123 thanks")
        XCTAssertEqual(url?.host, "vimeo.com")
    }

    func testYoutuBe() {
        let url = URLDetector.videoBearingURL(in: "https://youtu.be/dQw4w9WgXcQ")
        XCTAssertEqual(url?.host, "youtu.be")
    }

    func testTikTok() {
        let url = URLDetector.videoBearingURL(in: "https://tiktok.com/@user/video/123")
        XCTAssertEqual(url?.host, "tiktok.com")
    }

    func testYouTubeWithoutWWW() {
        let url = URLDetector.videoBearingURL(in: "https://youtube.com/watch?v=abc")
        XCTAssertEqual(url?.host, "youtube.com")
    }

    func testBilibiliVideo() {
        let url = URLDetector.videoBearingURL(in: "https://www.bilibili.com/video/BV1abc")
        XCTAssertEqual(url?.host, "www.bilibili.com")
    }

    func testMusicYouTubeSubdomain() {
        let url = URLDetector.videoBearingURL(in: "https://music.youtube.com/watch?v=abc")
        XCTAssertEqual(url?.host, "music.youtube.com")
    }

    func testDouyinShareCardProse() {
        let shareText = """
        9.94 :8pm 10/11 J@v.Sl jPx:/ 大结局 # 齐之芳# 娘要嫁人# 怀旧经典影视  https://v.douyin.com/8TclIuNm4ew/ 复制此链接，打开Dou音搜索，直接观看视频！
        """
        let url = URLDetector.firstDownloadableURL(in: shareText)
        XCTAssertEqual(url, "https://v.douyin.com/8TclIuNm4ew/")
    }

    func testDouyinShareCardWithoutScheme() {
        let shareText = "复制此链接 v.douyin.com/8TclIuNm4ew/ 打开Dou音"
        let url = URLDetector.firstDownloadableURL(in: shareText)
        XCTAssertEqual(url, "https://v.douyin.com/8TclIuNm4ew/")
    }
}
