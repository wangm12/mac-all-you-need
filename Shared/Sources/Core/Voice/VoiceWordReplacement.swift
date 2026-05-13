import Foundation

public enum VoiceWordReplacement {
    public static func apply(_ text: String, entries: [VoiceDictionaryEntry]) -> String {
        entries
            .filter { !$0.phrase.isEmpty }
            .sorted { $0.phrase.count > $1.phrase.count }
            .reduce(text) { current, entry in
                if shouldUseWordBoundaries(for: entry.phrase) {
                    return replacingLatinPhrase(entry.phrase, with: entry.replacement, in: current)
                }
                return current.replacingOccurrences(of: entry.phrase, with: entry.replacement)
            }
    }

    private static func shouldUseWordBoundaries(for phrase: String) -> Bool {
        phrase.unicodeScalars.contains { scalar in
            CharacterSet.alphanumerics.contains(scalar) && !isCJK(scalar)
        }
    }

    private static func replacingLatinPhrase(_ phrase: String, with replacement: String, in text: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        let pattern = "(?<![A-Za-z0-9_])\(escaped)(?![A-Za-z0-9_])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
        )
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400 ... 0x4DBF,
             0x4E00 ... 0x9FFF,
             0xF900 ... 0xFAFF,
             0x20000 ... 0x2A6DF,
             0x2A700 ... 0x2B73F,
             0x2B740 ... 0x2B81F,
             0x2B820 ... 0x2CEAF:
            true
        default:
            false
        }
    }
}
