@testable import Core
import XCTest

final class VoiceDictionaryCSVParserTests: XCTestCase {
    func testParsesRowsWithOptionalHeader() throws {
        let csv = """
        phrase,replacement
        海涛,江涛
        deploy,Deploy
        """
        let rows = try VoiceDictionaryCSVParser.parse(csv)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].phrase, "海涛")
        XCTAssertEqual(rows[0].replacement, "江涛")
    }

    func testParsesQuotedCommasAndSkipsComments() throws {
        let csv = """
        # dictionary backup
        "comma, one","fixed, one"
        plain,Simple
        """
        let rows = try VoiceDictionaryCSVParser.parse(csv)
        XCTAssertEqual(rows.map(\.phrase), ["comma, one", "plain"])
    }

    func testRejectsEmptyFile() {
        XCTAssertThrowsError(try VoiceDictionaryCSVParser.parse("   ")) { error in
            XCTAssertEqual(error as? VoiceDictionaryCSVParserError, .emptyFile)
        }
    }

    func testRejectsFileWithNoValidRows() {
        let csv = """
        phrase,replacement
        ,
        # only comments
        """
        XCTAssertThrowsError(try VoiceDictionaryCSVParser.parse(csv)) { error in
            XCTAssertEqual(error as? VoiceDictionaryCSVParserError, .noValidRows)
        }
    }

    func testParseCSVLineHandlesEscapedQuotes() {
        let fields = VoiceDictionaryCSVParser.parseCSVLine(#""say ""hi""",Hello"#)
        XCTAssertEqual(fields, [#"say "hi""#, "Hello"])
    }
}
