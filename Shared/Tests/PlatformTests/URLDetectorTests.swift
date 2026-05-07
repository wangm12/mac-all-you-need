import XCTest
@testable import Platform

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
}
