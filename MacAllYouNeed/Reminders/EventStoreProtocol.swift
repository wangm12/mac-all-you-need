import EventKit
import Foundation

/// Injectable EventKit boundary so tests never hit the real event store.
protocol EventStoreProtocol: Sendable {
    func requestFullAccessToReminders() async throws -> Bool
    func defaultCalendarForNewReminders() -> EKCalendar?
    func calendars(for entityType: EKEntityType) -> [EKCalendar]
    func save(_ reminder: EKReminder, commit: Bool) throws
    func remove(_ reminder: EKReminder, commit: Bool) throws
    func commit() throws
}

extension EKEventStore: EventStoreProtocol {}
