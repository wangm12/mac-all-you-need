import Core
import EventKit
import Foundation

enum RemindersServiceError: Error {
    case unsupportedStore
}

@MainActor
final class RemindersService {
    private let store: any EventStoreProtocol
    private(set) var authStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .reminder)

    init(store: any EventStoreProtocol = EKEventStore()) {
        self.store = store
    }

    func requestAccess() async throws -> Bool {
        let granted = try await store.requestFullAccessToReminders()
        authStatus = EKEventStore.authorizationStatus(for: .reminder)
        return granted
    }

    var isAuthorized: Bool {
        authStatus == .fullAccess
    }

    func availableLists() -> [ReminderListInfo] {
        let defaultCal = store.defaultCalendarForNewReminders()
        return store.calendars(for: .reminder).map { cal in
            ReminderListInfo(
                id: cal.calendarIdentifier,
                name: cal.title,
                isDefault: cal.calendarIdentifier == defaultCal?.calendarIdentifier
            )
        }
    }

    func createReminder(title: String, dueDate: ReminderDueDate?, listID: String?) throws -> CreatedReminder {
        // EKReminder requires a concrete EKEventStore. The protocol seam exists
        // so tests inject a fake RemindersWriter; the real write needs the store.
        guard let eventStore = store as? EKEventStore else {
            throw RemindersServiceError.unsupportedStore
        }
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title

        if let listID,
           let cal = store.calendars(for: .reminder).first(where: { $0.calendarIdentifier == listID }) {
            reminder.calendar = cal
        } else {
            reminder.calendar = store.defaultCalendarForNewReminders()
        }

        if let dueDate {
            var comps = dueDate.dateComponents
            comps.calendar = Calendar.current
            reminder.dueDateComponents = comps
        }

        try store.save(reminder, commit: true)

        return CreatedReminder(
            id: reminder.calendarItemIdentifier,
            title: title,
            listName: reminder.calendar?.title ?? "Reminders",
            dueDate: dueDate
        )
    }
}

/// Concrete `RemindersWriter` backed by `RemindersService`.
@MainActor
final class RemindersServiceWriter: RemindersWriter {
    private let service: RemindersService

    init(service: RemindersService) {
        self.service = service
    }

    func write(title: String, dueDate: ReminderDueDate?, listID: String?) async throws -> CreatedReminder {
        try service.createReminder(title: title, dueDate: dueDate, listID: listID)
    }
}
