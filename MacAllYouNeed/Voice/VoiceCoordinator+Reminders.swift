import Core
import Foundation

/// Plan 03 — Voice → Reminders. Keeps the reminder-specific surface of the
/// coordinator out of the main file so `VoiceCoordinator.swift` stays within
/// the type/file length budget. The dictation path lives in the main file and
/// is unchanged.
@MainActor
extension VoiceCoordinator {
    /// Entry point for the reminder hotkey. Sets the reminder intent for the
    /// next run, then starts recording exactly like dictation. When a recording
    /// is already in flight, this commits it (the hotkey is a toggle).
    func toggleReminderRecording() async {
        guard voiceRemindersEnabled() else { return }
        if state == .recording {
            await stopRecordingAndPaste()
            return
        }
        guard state == .idle else { return }
        activeIntent = .reminder
        await startRecording()
    }

    /// Promotes a `.dictation` run to `.reminder` when the transcript opens with
    /// a spoken reminder prefix. Never demotes a hotkey-forced intent; gated by
    /// `spokenPrefixEnabled`, and the Voice Reminders feature runtime state.
    func maybePromoteToReminderIntent(rawText: String?) {
        guard voiceRemindersEnabled(),
              activeIntent == .dictation,
              reminderSettings().spokenPrefixEnabled,
              let rawText,
              SpokenReminderPrefixDetector.isReminder(rawText)
        else { return }
        activeIntent = .reminder
        log.info("reminder intent — promoted from spoken prefix")
    }

    /// The reminder writer for the current run. Tests inject via
    /// `reminderWriterOverride`; production wires `RemindersServiceWriter`.
    func resolveReminderWriter() -> (any RemindersWriter)? {
        guard voiceRemindersEnabled() else { return nil }
        return reminderWriterOverride
    }

    /// Terminal reminder step: write to Apple Reminders, then tear the run down
    /// the same way the happy path does (idle, clear inflight, dismiss HUD) and
    /// reset the intent. Throws so the caller's catch surfaces an error HUD.
    func finishReminderRun(
        cleanedText: String,
        writer: any RemindersWriter,
        generation: Int
    ) async throws {
        let phase = ReminderWritePhase(writer: writer, settings: reminderSettings)
        let created: CreatedReminder
        if let remindersWorker {
            created = try await remindersWorker.performWrite {
                try await phase.execute(cleanedText: cleanedText)
            }
        } else {
            created = try await phase.execute(cleanedText: cleanedText)
        }
        lastCreatedReminder = created
        log.info("reminder written — list: \(created.listName, privacy: .public) hasDue: \(created.dueDate != nil, privacy: .public)")
        NotificationCenter.default.post(name: .voiceReminderCreated, object: created)
        guard isCurrentOperation(generation) else { return }
        teardownAfterReminderRun()
    }
}

extension Notification.Name {
    /// Posted with a `CreatedReminder` object after a spoken reminder is written
    /// to Apple Reminders. The Command Center popover listens to refresh.
    static let voiceReminderCreated = Notification.Name("com.macallyouneed.voiceReminderCreated")
}
