@testable import Platform
import XCTest

final class RegexBlocklistTests: XCTestCase {
    func testEmptyBlocklistMatchesNothing() {
        let blocklist = RegexBlocklist(patterns: [])
        XCTAssertFalse(blocklist.matches("anything"))
    }

    func testCreditCardPatternMatches() {
        let blocklist = RegexBlocklist(patterns: [#"\b(?:\d[ -]?){13,16}\b"#])
        XCTAssertTrue(blocklist.matches("4111 1111 1111 1111"))
        XCTAssertFalse(blocklist.matches("hello world"))
    }

    func testInvalidPatternIgnoredSilently() {
        let blocklist = RegexBlocklist(patterns: ["[unbalanced"])
        XCTAssertFalse(blocklist.matches("anything"))
    }

    func testValidatePatternThrowsForInvalid() {
        XCTAssertThrowsError(try RegexBlocklist.validate("[unbalanced"))
        XCTAssertNoThrow(try RegexBlocklist.validate(#"\d+"#))
    }
}
