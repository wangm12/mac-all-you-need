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

    func testStripsSpokenPrefixAndExtractsDueDate() async throws {
        let writer = MockReminderWriter()
        let phase = ReminderWritePhase(writer: writer, settings: { .default })
        let r = try await phase.execute(
            cleanedText: "Remind me to book a reservation Saturday morning at 10 o'clock"
        )
        XCTAssertEqual(r.title, "book a reservation")
        XCTAssertNotNil(r.dueDate)
        XCTAssertEqual(r.dueDate?.hour, 10)
    }

    func testParsesDueDateTag() async throws {
        let writer = MockReminderWriter()
        let phase = ReminderWritePhase(writer: writer, settings: { .default })
        let r = try await phase.execute(cleanedText: "Schedule dentist\nDUE:2026-06-15T10:00")
        XCTAssertEqual(r.title, "Schedule dentist")
        XCTAssertEqual(r.dueDate?.day, 15)
    }

    func testWriteFailurePropagates() async {
        let writer = FailingReminderWriter(message: "EventKit denied")
        let phase = ReminderWritePhase(writer: writer, settings: { .default })
        do {
            _ = try await phase.execute(cleanedText: "Buy milk")
            XCTFail("expected write to throw")
        } catch let error as FailingReminderWriter.Failure {
            XCTAssertEqual(error.message, "EventKit denied")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
