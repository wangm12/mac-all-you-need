import Foundation

/// Converts reminder cleanup output (or raw ASR fallback) into a title and optional due date.
public enum ReminderPayloadNormalizer {
    public static func prepare(
        _ raw: String,
        calendar: Calendar = .current
    ) -> (title: String, dueDate: ReminderDueDate?) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", nil) }

        var (title, dueDate) = ReminderDuePayloadParser.parse(trimmed)
        title = SpokenReminderPrefixDetector.normalizedTaskTitle(title)

        if dueDate == nil {
            let extraction = SpokenReminderDueDateExtractor.extract(from: trimmed, calendar: calendar)
            dueDate = extraction.dueDate
            if let matched = extraction.matchedText {
                title = removePhrase(title, phrase: matched)
            }
        }

        title = trimSchedulingTail(title)
        title = collapseWhitespace(title)

        if title.isEmpty {
            title = SpokenReminderPrefixDetector.normalizedTaskTitle(trimmed)
            title = trimSchedulingTail(title)
            title = collapseWhitespace(title)
        }

        return (title, dueDate)
    }

    private static func removePhrase(_ text: String, phrase: String) -> String {
        guard !phrase.isEmpty,
              let range = text.range(of: phrase, options: [.caseInsensitive, .diacriticInsensitive])
        else {
            return text
        }
        var result = text
        result.removeSubrange(range)
        return result
    }

    private static func trimSchedulingTail(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let tailPatterns = [
            #"\bon\s+(?:sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b.*$"#,
            #"\bat\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)?\b.*$"#,
            #"\b(?:tomorrow|tonight|today)\b.*$"#,
            #"\b(?:in the )?morning\b.*$"#,
            #"\b(?:in the )?afternoon\b.*$"#,
            #"\b(?:in the )?evening\b.*$"#
        ]
        for pattern in tailPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            }
        }
        return result
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.;"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
