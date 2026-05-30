@testable import Core
@testable import MacAllYouNeed
import XCTest

@MainActor
final class ReminderWritePhaseTests: XCTestCase {
    func testExtractsTitleFromCleanedText() async throws {
        let writer = MockReminderWriter()
        let phase = ReminderWritePhase(writer: writer, settings: { .default })
        let r = try await phase.execute(cleanedText: "Buy milk from Safeway")
        XCTAssertEqual(r.title, "Buy milk from Safeway")
        XCTAssertEqual(writer.created.count, 1)
    }

    func testParsesDueDateTag() async throws {
        let writer = MockReminderWriter()
        let phase = ReminderWritePhase(writer: writer, settings: { .default })
        let r = try await phase.execute(cleanedText: "Schedule dentist\nDUE:2026-06-15T10:00")
        XCTAssertEqual(r.title, "Schedule dentist")
        XCTAssertEqual(r.dueDate?.day, 15)
    }
}
