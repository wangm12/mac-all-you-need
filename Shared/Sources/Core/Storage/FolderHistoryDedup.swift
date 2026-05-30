import Foundation

/// Pure debounce/dedup logic for folder visit recording.
public enum FolderHistoryDedup {
    /// Returns true if the new path should be recorded (not a duplicate of the recent path).
    /// Debounce: the same path seen again within `debounceWindow` seconds is a duplicate.
    public static func shouldRecord(
        newPath: String,
        lastPath: String?,
        lastDate: Date?,
        debounceWindow: TimeInterval = 2.0,
        now: Date = Date()
    ) -> Bool {
        guard let lastPath, let lastDate else { return true }
        if newPath == lastPath {
            return now.timeIntervalSince(lastDate) > debounceWindow
        }
        return true
    }
}
