import Foundation

/// Encodes/decodes `ReminderSnapshot` to/from the App Group UserDefaults.
/// Read by the WidgetKit extension without requiring IPC.
public enum ReminderSnapshotStore {
    static let key = "reminders.snapshot"

    public static func save(_ snapshot: ReminderSnapshot, to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        }
    }

    public static func load(from defaults: UserDefaults) -> ReminderSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ReminderSnapshot.self, from: data)
    }
}
