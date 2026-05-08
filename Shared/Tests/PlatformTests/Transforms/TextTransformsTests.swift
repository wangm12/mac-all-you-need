@testable import Platform
import XCTest

final class TextTransformsTests: XCTestCase {
    func testLowercase() {
        XCTAssertEqual(TextTransforms.apply(.lowercase, to: "HeLLo"), "hello")
    }

    func testUppercase() {
        XCTAssertEqual(TextTransforms.apply(.uppercase, to: "Hello"), "HELLO")
    }

    func testTitleCase() {
        XCTAssertEqual(TextTransforms.apply(.titleCase, to: "the quick brown fox"), "The Quick Brown Fox")
    }

    func testTrim() {
        XCTAssertEqual(TextTransforms.apply(.trim, to: "  hi\n\t"), "hi")
    }

    func testStripHTML() {
        XCTAssertEqual(TextTransforms.apply(.stripHTML, to: "<b>bold</b>"), "bold")
    }

    func testPrettyJSON() {
        XCTAssertEqual(
            TextTransforms.apply(.prettyJSON, to: #"{"a":1,"b":[2,3]}"#),
            "{\n  \"a\" : 1,\n  \"b\" : [\n    2,\n    3\n  ]\n}"
        )
    }

    func testPrettyJSONFailsOnInvalid() {
        XCTAssertNil(TextTransforms.apply(.prettyJSON, to: "not json"))
    }

    func testMinifyJSON() {
        XCTAssertEqual(TextTransforms.apply(.minifyJSON, to: "{\n  \"a\": 1\n}"), "{\"a\":1}")
    }

    func testBase64Encode() {
        XCTAssertEqual(TextTransforms.apply(.base64Encode, to: "hi"), "aGk=")
    }

    func testBase64Decode() {
        XCTAssertEqual(TextTransforms.apply(.base64Decode, to: "aGk="), "hi")
    }

    func testBase64DecodeFailsOnInvalid() {
        XCTAssertNil(TextTransforms.apply(.base64Decode, to: "@@@"))
    }

    func testURLEncode() {
        XCTAssertEqual(TextTransforms.apply(.urlEncode, to: "a b/c"), "a%20b%2Fc")
    }

    func testURLDecode() {
        XCTAssertEqual(TextTransforms.apply(.urlDecode, to: "a%20b%2Fc"), "a b/c")
    }

    func testSortLines() {
        XCTAssertEqual(TextTransforms.apply(.sortLines, to: "b\na\nc"), "a\nb\nc")
    }

    func testDedupeLines() {
        XCTAssertEqual(TextTransforms.apply(.dedupeLines, to: "a\nb\na\nc\nb"), "a\nb\nc")
    }
}
