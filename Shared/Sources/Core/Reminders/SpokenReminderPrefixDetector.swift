import Foundation

public enum SpokenReminderPrefixDetector {
    static let prefixes: [String] = [
        "remind me to add a reminder to ",
        "remind me to add a reminder that ",
        "remind me to ",
        "remind me ",
        "set a reminder to ",
        "set a reminder for ",
        "take a reminder ",
        "add a reminder to ",
        "add a reminder that ",
        "create a reminder to ",
        "create a reminder that ",
        "make a reminder to ",
        "make a reminder that ",
        "remember to ",
        "don't forget to ",
        "make a note to "
    ]

    /// Returns true if the transcript begins with a known reminder prefix.
    public static func isReminder(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        return prefixes.contains { lower.hasPrefix($0) }
    }

    /// Returns the transcript with the reminder prefix stripped.
    public static func strippingPrefix(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var changed = true
        while changed {
            changed = false
            let lower = result.lowercased()
            for prefix in prefixes where lower.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                changed = true
                break
            }
        }
        return result
    }

    /// Strips nested reminder lead-ins until only the actionable task remains.
    public static func normalizedTaskTitle(_ text: String) -> String {
        strippingPrefix(text)
    }
}
