import XCTest
@testable import MacAllYouNeed

final class CompanionDownloadDeepLinkTests: XCTestCase {
    func testParsesCompanionWakeURL() {
        let url = URL(string: "mayn://companion/wake")!
        XCTAssertEqual(CompanionDownloadDeepLink.parse(url), .wake)
    }

    func testParsesCompanionDownloadURL() throws {
        let raw = "mayn://companion/download?url=https%3A%2F%2Fwww.douyin.com%2Fvideo%2F123&type=mp4&awemeId=123&title=test"
        let url = try XCTUnwrap(URL(string: raw))
        let payload = try XCTUnwrap(CompanionDownloadDeepLink.parse(url))
        guard case let .download(parsed) = payload else {
            return XCTFail("expected download action")
        }
        XCTAssertEqual(parsed.url, "https://www.douyin.com/video/123")
        XCTAssertEqual(parsed.mediaType, "mp4")
        XCTAssertEqual(parsed.awemeID, "123")
        XCTAssertEqual(parsed.title, "test")
    }

    func testRejectsNonCompanionHost() {
        let url = URL(string: "mayn://reminders/abc")!
        XCTAssertNil(CompanionDownloadDeepLink.parse(url))
    }

    func testIgnoresEmptyQueryValuesAndKeepsRequiredFields() throws {
        let raw = "mayn://companion/download?url=https%3A%2F%2Fwww.douyin.com%2Fvideo%2F123&type=mp4&title=test&referer=&pageURL="
        let url = try XCTUnwrap(URL(string: raw))
        let payload = try XCTUnwrap(CompanionDownloadDeepLink.parse(url))
        guard case let .download(parsed) = payload else {
            return XCTFail("expected download action")
        }

        XCTAssertEqual(parsed.url, "https://www.douyin.com/video/123")
        XCTAssertEqual(parsed.mediaType, "mp4")
        XCTAssertEqual(parsed.title, "test")
        XCTAssertNil(parsed.referer)
        XCTAssertNil(parsed.pageURL)
    }
}
