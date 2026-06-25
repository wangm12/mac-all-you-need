@testable import MacAllYouNeed
import XCTest

final class DownloadCoordinatorNormalizationTests: XCTestCase {
    func testNormalizeDouyinExtensionDispatchConvertsAwemeIdToCanonicalPageURL() {
        let normalized = DownloadCoordinator.normalizeDouyinExtensionDispatch(
            url: "https://v.douyin.com/abc/",
            title: "  demo title  ",
            mediaType: " mp4 ",
            pageURL: "https://www.douyin.com/share/video/7653855010903641353?foo=1",
            douyinAwemeID: nil
        )

        XCTAssertEqual(normalized.url, "https://www.douyin.com/video/7653855010903641353")
        XCTAssertEqual(normalized.pageURL, "https://www.douyin.com/video/7653855010903641353")
        XCTAssertEqual(normalized.awemeID, "7653855010903641353")
        XCTAssertNil(normalized.mediaType)
    }

    func testNormalizeDouyinExtensionDispatchPreservesNonDouyinURLs() {
        let normalized = DownloadCoordinator.normalizeDouyinExtensionDispatch(
            url: "https://example.com/video.mp4",
            title: nil,
            mediaType: "video/mp4",
            pageURL: nil,
            douyinAwemeID: nil
        )

        XCTAssertEqual(normalized.url, "https://example.com/video.mp4")
        XCTAssertNil(normalized.pageURL)
        XCTAssertNil(normalized.awemeID)
        XCTAssertEqual(normalized.mediaType, "video/mp4")
    }

    func testConcreteDestinationExpandsTemplateIntoLiteralFilename() {
        let destination = URL(fileURLWithPath: "/tmp/%(title)s.%(ext)s")
        let resolved = DownloadCoordinator.concreteDestination(
            from: destination,
            title: "hello / world",
            author: "作者",
            fallbackID: "7653855010903641353",
            ext: "mp4"
        )

        XCTAssertEqual(resolved.pathExtension, "mp4")
        XCTAssertFalse(resolved.lastPathComponent.contains("%("))
        XCTAssertFalse(resolved.lastPathComponent.contains("/"))
    }
}
