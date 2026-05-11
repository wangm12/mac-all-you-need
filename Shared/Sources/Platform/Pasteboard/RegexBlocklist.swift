import Foundation

public struct RegexBlocklist: @unchecked Sendable {
    private let regexes: [NSRegularExpression]

    public init(patterns: [String]) {
        regexes = patterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }

    public func matches(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return regexes.contains { $0.firstMatch(in: text, options: [], range: range) != nil }
    }

    public static func validate(_ pattern: String) throws {
        _ = try NSRegularExpression(pattern: pattern, options: [])
    }
}
