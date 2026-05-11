import AppKit
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
}
