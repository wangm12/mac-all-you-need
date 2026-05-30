import Core
import Foundation

/// Terminal phase for `.reminder` VoiceIntent — writes to EventKit instead of
/// pasting. Parallel to `PastePhase` for the dictation path.
@MainActor
final class ReminderWritePhase {
    private let writer: any RemindersWriter
    private let settings: () -> ReminderSettings

    init(writer: any RemindersWriter, settings: @escaping () -> ReminderSettings) {
        self.writer = writer
        self.settings = settings
    }

    /// Called after ASR + LLM cleanup with the cleaned text. Parses the title
    /// and optional DUE tag, then writes the reminder. Returns the created
    /// reminder or throws on failure.
    @discardableResult
    func execute(cleanedText: String) async throws -> CreatedReminder {
        let (title, dueDate) = ReminderDuePayloadParser.parse(cleanedText)
        let config = settings()
        return try await writer.write(title: title, dueDate: dueDate, listID: config.defaultListID)
    }
}
