import XCTest
@testable import Core

final class FilenameSanitizerTests: XCTestCase {
    func testStripsIllegalChars() { XCTAssertEqual(FilenameSanitizer.sanitize("a/b:c"), "a-b-c") }
    func testCollapsesDoubleDashes() { XCTAssertEqual(FilenameSanitizer.sanitize("a//b"), "a-b") }
    func testTrimsDashes() { XCTAssertEqual(FilenameSanitizer.sanitize("-hello-"), "hello") }
    func testEmptyBecomesUntitled() { XCTAssertEqual(FilenameSanitizer.sanitize(""), "untitled") }
    func testLengthCap() {
        let long = String(repeating: "a", count: 300)
        XCTAssertTrue(FilenameSanitizer.sanitize(long).count <= 200)
    }
}
