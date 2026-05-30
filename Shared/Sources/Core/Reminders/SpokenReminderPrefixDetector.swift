import Foundation

public enum SpokenReminderPrefixDetector {
    static let prefixes: [String] = [
        "remind me to ", "remind me ", "set a reminder to ", "set a reminder for ",
        "take a reminder ", "add a reminder to ", "create a reminder to ",
        "remember to ", "don't forget to ", "make a note to "
    ]

    /// Returns true if the transcript begins with a known reminder prefix.
    public static func isReminder(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        return prefixes.contains { lower.hasPrefix($0) }
    }

    /// Returns the transcript with the reminder prefix stripped.
    public static func strippingPrefix(_ text: String) -> String {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        for prefix in prefixes where lower.hasPrefix(prefix) {
            return String(trimmedText.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return text
    }
}
