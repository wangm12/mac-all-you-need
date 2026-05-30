import Core
import Foundation

/// Pure value type parsing the dock search bar into structured smart-search
/// filters. Slash operators (`/app:`, `/type:`, `/date:`) and a `/regex/`
/// delimiter form filter the clipboard history; everything else is free text.
///
/// Strict parsing: only tokens matching `^-?/(app|type|date):` are treated as
/// operators. `a/b` and other slash-containing tokens stay free text.
struct SmartSearchQuery: Equatable {
    var freeText: String = ""
    var appFilters: [String] = []
    var negatedApps: [String] = []
    var typeFilters: [String] = []
    var dateOnOrAfter: Date?

    /// Whole-query regex mode: set when the trimmed query is wrapped in `/.../`.
    var isRegex = false
    var regexPattern: String?
    /// Compiled regex; nil when the pattern is invalid (falls back to free text).
    var compiledRegex: NSRegularExpression?

    /// True when any structured operator (not just free text) is present.
    var hasOperators: Bool {
        !appFilters.isEmpty || !negatedApps.isEmpty || !typeFilters.isEmpty
            || dateOnOrAfter != nil || isRegex
    }

    /// Whether the free-text / regex portion of the query matches a record's
    /// visible text (preview) or its background OCR text. Structured operators
    /// (app/type/date) are applied separately by the predicate filter; this only
    /// covers the text-match dimension. An empty free-text non-regex query
    /// matches everything.
    func matchesText(_ preview: String, ocrText: String?) -> Bool {
        let haystacks = [preview, ocrText].compactMap { $0 }
        if isRegex {
            guard let re = compiledRegex else { return true }
            return haystacks.contains { hay in
                re.firstMatch(in: hay, range: NSRange(hay.startIndex..., in: hay)) != nil
            }
        }
        let needle = freeText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        return haystacks.contains { $0.lowercased().contains(needle) }
    }

    private static let operatorPattern = try? NSRegularExpression(
        pattern: #"^(-?)/(app|type|date):(.+)$"#, options: [.caseInsensitive]
    )

    init(_ raw: String, now: Date = Date(), calendar: Calendar = .current) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Whole-query regex: starts and ends with '/', at least one char between.
        if trimmed.count >= 2, trimmed.hasPrefix("/"), trimmed.hasSuffix("/"),
           !Self.looksLikeOperator(trimmed)
        {
            let pattern = String(trimmed.dropFirst().dropLast())
            if !pattern.isEmpty {
                isRegex = true
                regexPattern = pattern
                if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                    compiledRegex = re
                } else {
                    // Invalid regex: degrade to a literal free-text search.
                    isRegex = false
                    regexPattern = nil
                    freeText = trimmed
                }
                return
            }
        }

        var freeTokens: [String] = []
        for token in trimmed.split(separator: " ").map(String.init) {
            if let op = Self.parseOperator(token) {
                let lowered = op.value.lowercased()
                switch op.kind {
                case "app":
                    if op.negated { negatedApps.append(lowered) } else { appFilters.append(lowered) }
                case "type":
                    typeFilters.append(lowered)
                case "date":
                    if let date = Self.parseDate(op.value, now: now, calendar: calendar) {
                        // Latest lower bound wins if multiple date filters appear.
                        if let existing = dateOnOrAfter {
                            dateOnOrAfter = max(existing, date)
                        } else {
                            dateOnOrAfter = date
                        }
                    }
                default:
                    break
                }
            } else {
                freeTokens.append(token)
            }
        }
        freeText = freeTokens.joined(separator: " ")
    }

    private struct ParsedOperator {
        let negated: Bool
        let kind: String
        let value: String
    }

    private static func looksLikeOperator(_ s: String) -> Bool {
        operatorPattern?.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private static func parseOperator(_ token: String) -> ParsedOperator? {
        guard let re = operatorPattern else { return nil }
        let range = NSRange(token.startIndex..., in: token)
        guard let m = re.firstMatch(in: token, range: range),
              let negRange = Range(m.range(at: 1), in: token),
              let kindRange = Range(m.range(at: 2), in: token),
              let valRange = Range(m.range(at: 3), in: token) else { return nil }
        let negated = !token[negRange].isEmpty
        return ParsedOperator(
            negated: negated,
            kind: String(token[kindRange]).lowercased(),
            value: String(token[valRange])
        )
    }

    /// `today`, `Nd` (last N days), or `YYYY-MM` / `YYYY-MM-DD`.
    static func parseDate(_ raw: String, now: Date, calendar: Calendar) -> Date? {
        let lowered = raw.lowercased()
        if lowered == "today" {
            return calendar.startOfDay(for: now)
        }
        if lowered.hasSuffix("d"), let days = Int(lowered.dropLast()), days >= 0 {
            return calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now))
        }
        let formats = ["yyyy-MM-dd", "yyyy-MM"]
        for fmt in formats {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.calendar = calendar
            df.timeZone = calendar.timeZone
            df.dateFormat = fmt
            if let date = df.date(from: raw) { return date }
        }
        return nil
    }
}
