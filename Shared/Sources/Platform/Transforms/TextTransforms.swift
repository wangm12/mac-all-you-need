import AppKit
import CryptoKit
import Foundation

public enum TextTransform: String, CaseIterable, Sendable {
    case lowercase
    case uppercase
    case titleCase
    case trim
    case stripHTML
    case prettyJSON
    case minifyJSON
    case base64Encode
    case base64Decode
    case urlEncode
    case urlDecode
    case sortLines
    case dedupeLines
    case camelToSnake
    case snakeToCamel
    case timestampToDate
    case escapeHTML
    case unescapeHTML
    case md5Hash
    case reverseText
}

public enum TextTransforms {
    private static let componentEncodingAllowed: CharacterSet = {
        var set = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        set.insert(charactersIn: "abcdefghijklmnopqrstuvwxyz")
        set.insert(charactersIn: "0123456789-_.~")
        return set
    }()

    public static func apply(_ transform: TextTransform, to text: String) -> String? {
        switch transform {
        case .lowercase:
            return text.lowercased()
        case .uppercase:
            return text.uppercased()
        case .titleCase:
            return text.capitalized
        case .trim:
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .stripHTML:
            return stripHTML(text)
        case .prettyJSON:
            return rewriteJSON(text, options: [.prettyPrinted, .sortedKeys])
        case .minifyJSON:
            return rewriteJSON(text, options: [])
        case .base64Encode:
            return text.data(using: .utf8)?.base64EncodedString()
        case .base64Decode:
            guard let data = Data(base64Encoded: text),
                  let decoded = String(data: data, encoding: .utf8)
            else {
                return nil
            }
            return decoded
        case .urlEncode:
            return text.addingPercentEncoding(withAllowedCharacters: componentEncodingAllowed)
        case .urlDecode:
            return text.removingPercentEncoding
        case .sortLines:
            return text.split(separator: "\n", omittingEmptySubsequences: false).sorted().joined(separator: "\n")
        case .dedupeLines:
            var seen = Set<Substring>()
            return text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { seen.insert($0).inserted }
                .joined(separator: "\n")
        case .camelToSnake:
            return camelToSnake(text)
        case .snakeToCamel:
            return snakeToCamel(text)
        case .timestampToDate:
            return timestampToDate(text)
        case .escapeHTML:
            return text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#39;")
        case .unescapeHTML:
            return text
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&nbsp;", with: " ")
        case .md5Hash:
            guard let data = text.data(using: .utf8) else { return nil }
            let digest = Insecure.MD5.hash(data: data)
            return digest.map { String(format: "%02x", $0) }.joined()
        case .reverseText:
            return String(text.reversed())
        }
    }

    private static func stripHTML(_ html: String) -> String? {
        guard let data = html.data(using: .utf8),
              let attr = NSAttributedString(html: data, documentAttributes: nil)
        else {
            return nil
        }
        return attr.string
    }

    private static func rewriteJSON(_ text: String, options: JSONSerialization.WritingOptions) -> String? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let encoded = try? JSONSerialization.data(withJSONObject: object, options: options),
              let out = String(data: encoded, encoding: .utf8)
        else {
            return nil
        }
        return out
    }

    private static func camelToSnake(_ text: String) -> String {
        // Insert _ before a cap that follows a lowercase letter ("fooBar" → "foo_Bar").
        // Insert _ before a cap that is followed by a lowercase letter when it is
        // itself preceded by another cap ("XMLParser" → "XML_Parser" → "xml_parser").
        // This two-pass approach handles both plain camelCase and acronym-prefixed names.
        var s = text
        // Pass 1: acronym boundary — e.g. "XML" + "Parser" → "XML_Parser"
        if let regex = try? NSRegularExpression(pattern: "([A-Z]+)([A-Z][a-z])") {
            s = regex.stringByReplacingMatches(
                in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1_$2"
            )
        }
        // Pass 2: standard camel boundary — e.g. "xml_Parser" → "xml__parser" → no, just lowercase cap
        if let regex = try? NSRegularExpression(pattern: "([a-z\\d])([A-Z])") {
            s = regex.stringByReplacingMatches(
                in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1_$2"
            )
        }
        return s.lowercased()
    }

    private static func snakeToCamel(_ text: String) -> String {
        let parts = text.components(separatedBy: "_")
        guard let first = parts.first else { return text }
        return first + parts.dropFirst().map { $0.capitalized }.joined()
    }

    private static func timestampToDate(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let timestamp = Double(trimmed) else { return nil }
        let date = timestamp > 1_000_000_000_000
            ? Date(timeIntervalSince1970: timestamp / 1000)
            : Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
