import AppIntents
import Foundation

@available(macOS 14, *)
struct CompleteReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Reminder"

    @Parameter(title: "Reminder ID") var reminderID: String

    func perform() async throws -> some IntentResult {
        // The widget process has limited EventKit access. Hand the request to
        // the main app via the shared App Group defaults; the app marks the
        // reminder complete the next time it observes the request.
        let defaults = UserDefaults(suiteName: "group.com.macallyouneed.shared")
        defaults?.set(reminderID, forKey: "reminders.completeRequest")
        return .result()
    }
}
