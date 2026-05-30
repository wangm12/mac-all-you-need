@testable import Core
import XCTest

final class ReminderDuePayloadParserTests: XCTestCase {
    func testParsesPlainTitle() {
        let (title, due) = ReminderDuePayloadParser.parse("Buy milk")
        XCTAssertEqual(title, "Buy milk")
        XCTAssertNil(due)
    }

    func testParsesTitleWithDueDate() {
        let (title, due) = ReminderDuePayloadParser.parse("Buy milk\nDUE:2026-06-01T09:00")
        XCTAssertEqual(title, "Buy milk")
        XCTAssertEqual(due?.year, 2026)
        XCTAssertEqual(due?.hour, 9)
    }

    func testParsesDateWithoutTime() {
        let (_, due) = ReminderDuePayloadParser.parse("Task\nDUE:2026-06-01")
        XCTAssertEqual(due?.year, 2026)
        XCTAssertNil(due?.hour)
    }

    func testInvalidDUETagIsIgnored() {
        let (title, due) = ReminderDuePayloadParser.parse("Task\nDUE:invalid")
        XCTAssertEqual(title, "Task")
        XCTAssertNil(due)
    }
}
