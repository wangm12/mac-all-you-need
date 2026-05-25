import Foundation

/// How far back clipboard rows are considered for browsing the history surface
/// (main window, dock, XPC). Aligns with Storage → **Maximum age**
/// (`retention.maxAgeDays`) and the row cap **Maximum items** (`retention.maxItems`).
public enum ClipboardHistoryWindow {
    public static func listParameters(
        now: Date = Date(),
        defaults: UserDefaults = AppGroupSettings.defaults
    ) -> (modifiedOnOrAfter: Date?, fetchLimit: Int) {
        let maxAgeDays = defaults.object(forKey: "retention.maxAgeDays") as? Int ?? 30
        let maxItems = defaults.object(forKey: "retention.maxItems") as? Int ?? 1000
        let cutoff: Date? = maxAgeDays > 0
            ? Calendar.current.date(byAdding: .day, value: -maxAgeDays, to: now)
            : nil
        return (cutoff, max(1, min(maxItems, 100_000)))
    }
}
