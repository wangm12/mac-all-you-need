import Foundation

public enum CaseStyle: String, Codable, Sendable, CaseIterable {
    case titleCase, camelCase, snakeCase, kebabCase, unchanged

    public func apply(to s: String) -> String {
        switch self {
        case .titleCase: return s.capitalized
        case .camelCase:
            let words = s.components(separatedBy: " ")
            return (words.first?.lowercased() ?? "") + words.dropFirst().map { $0.capitalized }.joined()
        case .snakeCase: return s.lowercased().replacingOccurrences(of: " ", with: "_")
        case .kebabCase: return s.lowercased().replacingOccurrences(of: " ", with: "-")
        case .unchanged: return s
        }
    }
}

public enum NamingPattern: Codable, Sendable {
    case text(caseStyle: CaseStyle)
    case datePrefix(caseStyle: CaseStyle)   // YYYY-MM-DD_title
    case sequence(prefix: String)           // prefix_001

    public func render(title: String, date: Date = Date(), index: Int = 0) -> String {
        switch self {
        case .text(let cs): return cs.apply(to: title)
        case .datePrefix(let cs):
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            return "\(fmt.string(from: date))_\(cs.apply(to: title))"
        case .sequence(let prefix):
            return String(format: "%@_%03d", prefix, index)
        }
    }
}
