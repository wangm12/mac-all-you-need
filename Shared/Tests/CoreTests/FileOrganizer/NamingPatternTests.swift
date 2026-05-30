import XCTest
@testable import Core

final class NamingPatternTests: XCTestCase {
    func testTitleCase() { XCTAssertEqual(CaseStyle.titleCase.apply(to: "hello world"), "Hello World") }
    func testSnakeCase() { XCTAssertEqual(CaseStyle.snakeCase.apply(to: "Hello World"), "hello_world") }
    func testDatePrefixHasDate() {
        let name = NamingPattern.datePrefix(caseStyle: .unchanged).render(title: "Report", date: Date())
        XCTAssertTrue(name.contains("-"))
        XCTAssertTrue(name.hasSuffix("_Report"))
    }
    func testSequenceFormats3Digits() {
        XCTAssertEqual(NamingPattern.sequence(prefix: "IMG").render(title: "", index: 5), "IMG_005")
    }
}
