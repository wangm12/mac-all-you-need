@testable import Core
import Foundation
@testable import MacAllYouNeed

/// Shared in-memory writer used by reminder phase + coordinator intent tests.
final class MockReminderWriter: RemindersWriter, @unchecked Sendable {
    private(set) var created: [CreatedReminder] = []
    private let lock = NSLock()

    func write(title: String, dueDate: ReminderDueDate?, listID: String?) async throws -> CreatedReminder {
        let r = CreatedReminder(id: UUID().uuidString, title: title, listName: "Inbox", dueDate: dueDate)
        lock.lock()
        created.append(r)
        lock.unlock()
        return r
    }
}
