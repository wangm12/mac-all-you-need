@testable import MacAllYouNeed
import XCTest

final class ContentExtractorTests: XCTestCase {
    func testExtractsPlainText() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try "Hello world".write(to: url, atomically: true, encoding: .utf8)
        let content = await ContentExtractor.shared.extract(from: url)
        XCTAssertEqual(content.kind, .text)
        XCTAssertTrue(content.snippet.contains("Hello"))
    }
    func testUnknownFileReturnsUnknownKind() async {
        let url = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID()).xyz")
        let content = await ContentExtractor.shared.extract(from: url)
        XCTAssertEqual(content.kind, .unknown)
    }
}
