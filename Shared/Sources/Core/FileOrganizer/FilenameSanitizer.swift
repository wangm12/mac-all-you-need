import Foundation

public enum FilenameSanitizer {
    static let illegalChars = CharacterSet(charactersIn: "/:\\*?\"<>|")
    static let maxLength = 200

    public static func sanitize(_ raw: String, extension ext: String? = nil) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.components(separatedBy: illegalChars).joined(separator: "-")
        // Collapse multiple spaces/dashes
        while s.contains("--") { s = s.replacingOccurrences(of: "--", with: "-") }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        // Length cap (leave room for extension)
        let extLen = ext.map { $0.count + 1 } ?? 0
        if s.count + extLen > maxLength {
            s = String(s.prefix(maxLength - extLen))
        }
        return s.isEmpty ? "untitled" : s
    }

    public static func sanitizeWithExtension(name: String, ext: String) -> String {
        let sanitizedName = sanitize(name, extension: ext)
        return "\(sanitizedName).\(ext)"
    }
}
