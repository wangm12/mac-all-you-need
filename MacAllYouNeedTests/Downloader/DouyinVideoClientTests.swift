import XCTest
@testable import MacAllYouNeed

final class DouyinVideoClientTests: XCTestCase {
    func testExtractAwemeIDFromVideoURL() {
        XCTAssertEqual(
            DouyinVideoClient.extractAwemeID(from: "https://www.douyin.com/video/7653855010903641353"),
            "7653855010903641353"
        )
    }

    func testExtractAwemeIDFromModalQuery() {
        XCTAssertEqual(
            DouyinVideoClient.extractAwemeID(from: "https://www.douyin.com/share/video/123?modal_id=7653855010903641353"),
            "7653855010903641353"
        )
    }

    func testAPISupportInjectsSyntheticMsTokenInCookieHeader() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cookieFile = dir.appendingPathComponent("cookies.txt")
        let netscape = """
        .douyin.com\tTRUE\t/\tTRUE\t1893456000\tsessionid\ttest-session
        """
        try? netscape.write(to: cookieFile, atomically: true, encoding: .utf8)

        let context = DouyinAPISupport.requestContext(from: cookieFile)
        XCTAssertNotNil(context)
        let header = DouyinAPISupport.cookieHeader(cookieMap: context!.cookieMap, msToken: context!.msToken)
        XCTAssertNotNil(header)
        XCTAssertTrue(header?.contains("sessionid=test-session") == true)
        XCTAssertTrue(header?.contains("msToken=\(context!.msToken)") == true)
    }

    func testQueryAndCookieHeaderShareMsToken() {
        let map = ["sessionid": "abc"]
        let msToken = "fixed-token-for-test=="
        let query = DouyinAPISupport.defaultWebQueryItems(
            msToken: msToken,
            extra: [.init(name: "aweme_id", value: "123")]
        )
        let header = DouyinAPISupport.cookieHeader(cookieMap: map, msToken: msToken)
        XCTAssertEqual(query.first(where: { $0.name == "msToken" })?.value, msToken)
        XCTAssertTrue(header?.contains("msToken=\(msToken)") == true)
    }

    func testDefaultWebQueryItemsOverwritesAid() {
        let query = DouyinAPISupport.defaultWebQueryItems(
            msToken: "token",
            extra: [
                .init(name: "aweme_id", value: "7653855010903641353"),
                .init(name: "aid", value: "1128")
            ]
        )
        let aidValues = query.filter { $0.name == "aid" }.map(\.value)
        XCTAssertEqual(aidValues, ["1128"])
    }

    func testExtractAwemeIDFromNoteURL() {
        XCTAssertEqual(
            DouyinVideoClient.extractAwemeID(from: "https://www.douyin.com/note/7653855010903641353"),
            "7653855010903641353"
        )
    }

    func testSignedURLAddsXBogus() {
        let url = DouyinAPISupport.signedURL(
            path: "/aweme/v1/web/aweme/detail/",
            queryItems: [
                .init(name: "aweme_id", value: "7653855010903641353"),
                .init(name: "aid", value: "6383")
            ]
        )
        XCTAssertNotNil(url)
        XCTAssertTrue(url?.absoluteString.contains("X-Bogus=") == true)
    }

    func testSignedURLWithABogusAddsToken() {
        let url = DouyinAPISupport.signedURLWithABogus(
            path: "/aweme/v1/web/aweme/detail/",
            queryItems: [
                .init(name: "aweme_id", value: "7653855010903641353"),
                .init(name: "aid", value: "6383")
            ]
        )
        XCTAssertNotNil(url)
        XCTAssertTrue(url?.absoluteString.contains("&a_bogus=") == true)
    }

    /// SM3 official test vector (GM/T 0004-2012).
    func testSM3KnownVector() {
        XCTAssertEqual(
            SM3.hashHex(Array("abc".utf8)),
            "66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0"
        )
    }

    /// Byte-for-byte match against the reference `abogus.py` for fixed inputs.
    func testABogusMatchesReferenceVector() {
        let params = "device_platform=webapp&aid=6383&aweme_id=7653855010903641353&msToken=ABC123%3D%3D"
        let ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            + "(KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36"
        let fp = "1536|864|1560|939|0|0|0|0|1536|864|1536|864|1536|864|24|24|Win32"
        let sig = DouyinABogus.generate(
            params: params,
            body: "",
            userAgent: ua,
            fingerprint: fp,
            randomPrefix: Array(1 ... 12),
            startTimeMillis: 1_750_000_000_000,
            endTimeMillis: 1_750_000_000_005
        )
        XCTAssertEqual(
            sig.aBogus,
            "DfmpkD62kjEsdEu85ldLfY3q63p3YM730SVkMD2fCV31QL39HMYD9exobHzvbYRjxG/"
                + "ZIeujy4hbT3ohrQc981wf9W4x/2AgQfSkKl5Q5xSSs1X9eghgJ04qmkt5SMx2RvB-"
                + "rOXmqhZHzYjh09oHmhK4bIOwu3GMRE=="
        )
    }
}
