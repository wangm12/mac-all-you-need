import Foundation

public enum SpokenReminderDueDateExtractor {
    public struct Extraction: Equatable, Sendable {
        public let dueDate: ReminderDueDate?
        public let matchedText: String?

        public init(dueDate: ReminderDueDate?, matchedText: String?) {
            self.dueDate = dueDate
            self.matchedText = matchedText
        }
    }

    /// Finds the best natural-language date/time mention in spoken reminder text.
    public static func extract(
        from text: String,
        calendar: Calendar = .current
    ) -> Extraction {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Extraction(dueDate: nil, matchedText: nil) }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return Extraction(dueDate: nil, matchedText: nil)
        }

        let ns = trimmed as NSString
        let matches = detector.matches(in: trimmed, options: [], range: NSRange(location: 0, length: ns.length))
        guard let best = selectBestMatch(matches) else {
            return Extraction(dueDate: nil, matchedText: nil)
        }

        guard let date = best.date else { return Extraction(dueDate: nil, matchedText: nil) }
        let matchedText = ns.substring(with: best.range)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return Extraction(dueDate: nil, matchedText: nil)
        }

        let hasTime = components.hour != nil
            && (components.hour != 0 || components.minute != 0 || matchedTextLooksTimed(matchedText))
        let dueDate = ReminderDueDate(
            year: year,
            month: month,
            day: day,
            hour: hasTime ? components.hour : nil,
            minute: hasTime ? (components.minute ?? 0) : nil
        )
        return Extraction(dueDate: dueDate, matchedText: matchedText)
    }

    private static func selectBestMatch(_ matches: [NSTextCheckingResult]) -> NSTextCheckingResult? {
        matches
            .filter { $0.date != nil }
            .max { lhs, rhs in
                let lhsScore = matchScore(lhs)
                let rhsScore = matchScore(rhs)
                if lhsScore == rhsScore {
                    return lhs.range.length < rhs.range.length
                }
                return lhsScore < rhsScore
            }
    }

    private static func matchScore(_ match: NSTextCheckingResult) -> Int {
        var score = match.range.length
        if match.date?.hasTimeComponent == true { score += 100 }
        return score
    }

    private static func matchedTextLooksTimed(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("am")
            || lower.contains("pm")
            || lower.contains("o'clock")
            || lower.contains("oclock")
            || lower.contains(":")
            || lower.contains("morning")
            || lower.contains("afternoon")
            || lower.contains("evening")
            || lower.contains("noon")
            || lower.contains("midnight")
    }
}

private extension Date {
    var hasTimeComponent: Bool {
        let hour = Calendar.current.component(.hour, from: self)
        let minute = Calendar.current.component(.minute, from: self)
        return hour != 0 || minute != 0
    }
}
