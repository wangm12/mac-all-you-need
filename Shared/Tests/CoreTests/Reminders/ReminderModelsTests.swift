@testable import Core
import XCTest

final class ReminderModelsTests: XCTestCase {
    func testVoiceIntentCasesPresent() {
        XCTAssertTrue(VoiceIntent.allCases.contains(.dictation))
        XCTAssertTrue(VoiceIntent.allCases.contains(.reminder))
    }

    func testCreatedReminderHoldsTitleListAndDue() {
        let due = ReminderDueDate(year: 2026, month: 6, day: 1, hour: 9, minute: 0)
        let r = CreatedReminder(id: "x-1", title: "Buy milk", listName: "Inbox", dueDate: due)
        XCTAssertEqual(r.title, "Buy milk")
        XCTAssertEqual(r.dueDate?.hour, 9)
    }

    func testReminderDueDateRoundTripsThroughDateComponents() {
        let due = ReminderDueDate(year: 2026, month: 6, day: 1, hour: 9, minute: 0)
        XCTAssertEqual(due.dateComponents.year, 2026)
        XCTAssertEqual(due.dateComponents.minute, 0)
    }

    func testSnapshotCodableRoundTrip() throws {
        let snap = ReminderSnapshot(lists: [.init(id: "1", name: "Inbox")], recentReminders: [])
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(ReminderSnapshot.self, from: data)
        XCTAssertEqual(decoded.lists.count, 1)
    }
}
