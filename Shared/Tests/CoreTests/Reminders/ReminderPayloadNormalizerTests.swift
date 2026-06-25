@testable import Core
import XCTest

final class ReminderPayloadNormalizerTests: XCTestCase {
    func testStripsReminderLeadIn() {
        let prepared = ReminderPayloadNormalizer.prepare("remind me to call the dentist")
        XCTAssertEqual(prepared.title, "call the dentist")
        XCTAssertNil(prepared.dueDate)
    }

    func testParsesDueTagAndStripsLeadIn() {
        let prepared = ReminderPayloadNormalizer.prepare(
            "Remind me to schedule dentist\nDUE:2026-06-15T10:00"
        )
        XCTAssertEqual(prepared.title, "schedule dentist")
        XCTAssertEqual(prepared.dueDate?.day, 15)
        XCTAssertEqual(prepared.dueDate?.hour, 10)
    }

    func testExtractsSpokenDateTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        let prepared = ReminderPayloadNormalizer.prepare(
            "remind me to book a reservation Saturday morning at 10 o'clock",
            calendar: calendar
        )
        XCTAssertEqual(prepared.title, "book a reservation")
        XCTAssertNotNil(prepared.dueDate)
        XCTAssertEqual(prepared.dueDate?.hour, 10)
        XCTAssertEqual(prepared.dueDate?.day, 27)
    }
}
