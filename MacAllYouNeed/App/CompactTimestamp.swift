import Foundation

/// Compact relative-time formatter — "now", "3m", "2h", "5d", "2mo", "1y".
/// `RelativeDateTimeFormatter(.abbreviated)` produces things like "3 min,
/// 43 sec" which is too noisy for tight list rows.
enum CompactTimestamp {
    static func format(_ date: Date, relativeTo now: Date = Date()) -> String {
        let secs = max(0, now.timeIntervalSince(date))
        if secs < 60 { return "now" }
        let mins = Int(secs / 60)
        if mins < 60 { return "\(mins)m" }
        let hours = mins / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 30 { return "\(days)d" }
        let months = days / 30
        if months < 12 { return "\(months)mo" }
        return "\(months / 12)y"
    }
}
