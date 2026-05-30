import XCTest
@testable import Core

final class ExtractedContentTests: XCTestCase {
    func testCodableRoundTripPreservesFields() throws {
        let content = ExtractedContent(
            originalURL: URL(fileURLWithPath: "/tmp/IMG_001.png"),
            utTypeIdentifier: "public.png",
            kind: .image,
            snippet: "INVOICE 2026",
            metadata: ["width": "1024"]
        )
        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(ExtractedContent.self, from: data)
        XCTAssertEqual(decoded.kind, .image)
        XCTAssertEqual(decoded.snippet, "INVOICE 2026")
        XCTAssertEqual(decoded.metadata["width"], "1024")
    }
}
