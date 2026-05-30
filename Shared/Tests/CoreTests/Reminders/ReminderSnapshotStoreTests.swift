@testable import Core
import XCTest

final class ReminderSnapshotStoreTests: XCTestCase {
    func testSaveAndLoad() {
        let defaults = UserDefaults(suiteName: "test.reminders.snapshot.\(UUID())")!
        let snap = ReminderSnapshot(lists: [.init(id: "1", name: "Inbox")], recentReminders: [])
        ReminderSnapshotStore.save(snap, to: defaults)
        let loaded = ReminderSnapshotStore.load(from: defaults)
        XCTAssertEqual(loaded?.lists.count, 1)
    }
}
