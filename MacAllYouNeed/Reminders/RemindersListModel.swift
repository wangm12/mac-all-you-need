import Core
import EventKit
import Foundation
import Observation

@MainActor
@Observable
final class RemindersListModel {
    var reminders: [CreatedReminder] = []
    var availableLists: [ReminderListInfo] = []
    var isLoading = false
    var authorizationStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .reminder)

    private let service: RemindersService
    private let snapshotDefaults: UserDefaults

    init(service: RemindersService, snapshotDefaults: UserDefaults = AppGroupSettings.defaults) {
        self.service = service
        self.snapshotDefaults = snapshotDefaults
    }

    func refresh() async {
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
        guard authorizationStatus == .fullAccess else { return }
        isLoading = true
        defer { isLoading = false }
        availableLists = service.availableLists()
        // Persist a snapshot so the WidgetKit extension can render without IPC.
        let snap = ReminderSnapshot(lists: availableLists, recentReminders: reminders)
        ReminderSnapshotStore.save(snap, to: snapshotDefaults)
    }

    func requestAccess() async {
        _ = try? await service.requestAccess()
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    }

    /// Records a reminder just created by the voice pipeline so the popover and
    /// widget snapshot reflect it immediately.
    func record(_ reminder: CreatedReminder) {
        reminders.insert(reminder, at: 0)
        reminders = Array(reminders.prefix(20))
        let snap = ReminderSnapshot(lists: availableLists, recentReminders: reminders)
        ReminderSnapshotStore.save(snap, to: snapshotDefaults)
    }
}
