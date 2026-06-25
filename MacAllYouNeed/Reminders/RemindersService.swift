import Core
import EventKit
import Foundation

enum RemindersServiceError: LocalizedError {
    case unsupportedStore
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .unsupportedStore:
            return "Internal error: unexpected EventKit store type."
        case .notAuthorized:
            return "Mac All You Need doesn't have permission to access Reminders. Grant access in System Settings → Privacy & Security → Reminders."
        }
    }
}

@MainActor
final class RemindersService {
    private let store: any EventStoreProtocol

    init(store: any EventStoreProtocol = EKEventStore()) {
        self.store = store
    }

    func requestAccess() async throws -> Bool {
        let granted = try await store.requestFullAccessToReminders()
        return granted
    }

    /// Requests Reminders access when status is still undetermined, then re-checks.
    @discardableResult
    func ensureAuthorized() async throws -> Bool {
        if isAuthorized { return true }
        let granted = try await requestAccess()
        return granted && isAuthorized
    }

    var isAuthorized: Bool {
        // Re-read the live status — the cached authStatus may lag after the user
        // grants or revokes permission in System Settings.
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized:
            true
        default:
            false
        }
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
        guard isAuthorized else {
            throw RemindersServiceError.notAuthorized
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
        guard try await service.ensureAuthorized() else {
            throw RemindersServiceError.notAuthorized
        }
        return try service.createReminder(title: title, dueDate: dueDate, listID: listID)
    }
}
