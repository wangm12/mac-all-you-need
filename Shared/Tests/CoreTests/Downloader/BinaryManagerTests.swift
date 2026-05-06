@testable import Core
import CryptoKit
import XCTest

final class BinaryManagerTests: XCTestCase {
    var dir: URL!
    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("bm-\(UUID())", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testVerifyFailsOnHashMismatch() throws {
        let url = dir.appendingPathComponent("yt-dlp")
        try Data("not the real binary".utf8).write(to: url)
        XCTAssertThrowsError(try BinaryManager.verify(at: url, expectedSHA256: "0000"))
    }

    func testVerifySucceedsOnMatch() throws {
        let url = dir.appendingPathComponent("yt-dlp")
        let data = Data("hello".utf8)
        try data.write(to: url)
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertNoThrow(try BinaryManager.verify(at: url, expectedSHA256: sha))
    }
}
