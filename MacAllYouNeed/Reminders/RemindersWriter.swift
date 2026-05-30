import Core
import Foundation

/// Injectable write seam — parallel to `pasterOverride` in VoiceCoordinator.
/// For `.reminder` intent the coordinator routes the cleaned title here instead
/// of pasting.
protocol RemindersWriter: Sendable {
    func write(title: String, dueDate: ReminderDueDate?, listID: String?) async throws -> CreatedReminder
}
