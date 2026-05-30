import Foundation

public enum ReminderDuePayloadParser {
    /// Parses the LLM summarizer output. Returns (title, dueDate?).
    /// The LLM may append a `DUE:` tag on a new line.
    public static func parse(_ raw: String) -> (title: String, dueDate: ReminderDueDate?) {
        let lines = raw.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        var titleLines: [String] = []
        var dueDate: ReminderDueDate?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("DUE:") {
                dueDate = parseDUETag(String(trimmed.dropFirst(4)))
            } else if !trimmed.isEmpty {
                titleLines.append(trimmed)
            }
        }

        let title = titleLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return (title.isEmpty ? raw.trimmingCharacters(in: .whitespacesAndNewlines) : title, dueDate)
    }

    /// Format: `YYYY-MM-DD` or `YYYY-MM-DDTHH:mm`.
    static func parseDUETag(_ s: String) -> ReminderDueDate? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.components(separatedBy: "T")
        let datePart = parts[0]
        let timePart = parts.count > 1 ? parts[1] : nil

        let dateComps = datePart.components(separatedBy: "-")
        guard dateComps.count == 3,
              let year = Int(dateComps[0]),
              let month = Int(dateComps[1]),
              let day = Int(dateComps[2])
        else { return nil }

        var hour: Int?
        var minute: Int?
        if let timePart {
            let timeComps = timePart.components(separatedBy: ":")
            hour = Int(timeComps[0])
            minute = timeComps.count > 1 ? Int(timeComps[1]) : 0
        }

        return ReminderDueDate(year: year, month: month, day: day, hour: hour, minute: minute)
    }
}
