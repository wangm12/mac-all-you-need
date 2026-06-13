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

    func testCamelToSnake() {
        XCTAssertEqual(TextTransforms.apply(.camelToSnake, to: "camelCaseString"), "camel_case_string")
        XCTAssertEqual(TextTransforms.apply(.camelToSnake, to: "myVariable"), "my_variable")
        XCTAssertEqual(TextTransforms.apply(.camelToSnake, to: "alreadylower"), "alreadylower")
        // Consecutive-caps (acronym) cases
        XCTAssertEqual(TextTransforms.apply(.camelToSnake, to: "XMLParser"), "xml_parser")
        XCTAssertEqual(TextTransforms.apply(.camelToSnake, to: "HTTPSConnection"), "https_connection")
        XCTAssertEqual(TextTransforms.apply(.camelToSnake, to: "parseHTML"), "parse_html")
    }

    func testSnakeToCamel() {
        XCTAssertEqual(TextTransforms.apply(.snakeToCamel, to: "camel_case_string"), "camelCaseString")
        XCTAssertEqual(TextTransforms.apply(.snakeToCamel, to: "my_variable"), "myVariable")
        XCTAssertEqual(TextTransforms.apply(.snakeToCamel, to: "nounderscore"), "nounderscore")
    }

    func testTimestampToDateSeconds() {
        // 2024-01-15 00:00:00 UTC = 1705276800
        let result = TextTransforms.apply(.timestampToDate, to: "1705276800")
        XCTAssertNotNil(result)
        XCTAssert(result?.contains("2024") == true)
    }

    func testTimestampToDateMilliseconds() {
        // millis > 1_000_000_000_000 branch
        let result = TextTransforms.apply(.timestampToDate, to: "1705276800000")
        XCTAssertNotNil(result)
        XCTAssert(result?.contains("2024") == true)
    }

    func testTimestampToDateInvalid() {
        XCTAssertNil(TextTransforms.apply(.timestampToDate, to: "not-a-number"))
    }

    func testEscapeHTML() {
        XCTAssertEqual(TextTransforms.apply(.escapeHTML, to: "<b>Hello & \"World\"</b>"), "&lt;b&gt;Hello &amp; &quot;World&quot;&lt;/b&gt;")
    }

    func testUnescapeHTML() {
        XCTAssertEqual(TextTransforms.apply(.unescapeHTML, to: "&lt;b&gt;Hello &amp; &quot;World&quot;&lt;/b&gt;"), "<b>Hello & \"World\"</b>")
    }

    func testMd5Hash() {
        // md5("hello") = 5d41402abc4b2a76b9719d911017c592
        XCTAssertEqual(TextTransforms.apply(.md5Hash, to: "hello"), "5d41402abc4b2a76b9719d911017c592")
    }

    func testReverseText() {
        XCTAssertEqual(TextTransforms.apply(.reverseText, to: "hello"), "olleh")
        XCTAssertEqual(TextTransforms.apply(.reverseText, to: "abc"), "cba")
    }
}
