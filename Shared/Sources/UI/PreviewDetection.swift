import AppKit
import Foundation

public enum DetectedKind: Equatable {
    case color(NSColor)
    case url(URL)
    case code(language: String, body: String)
    case plain(String)
}

public enum PreviewDetection {
    public static func detect(_ text: String) -> DetectedKind {
        if let color = parseColor(text) { return .color(color) }
        if let url = URL(string: text), url.scheme == "http" || url.scheme == "https" {
            return .url(url)
        }
        if looksLikeCode(text) { return .code(language: guessLanguage(text), body: text) }
        return .plain(text)
    }

    private static func parseColor(_ s: String) -> NSColor? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("#") else { return nil }
        let hexStr = t.dropFirst()
        guard hexStr.count == 6, let hex = UInt64(hexStr, radix: 16) else { return nil }
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        return NSColor(red: r, green: g, blue: b, alpha: 1)
    }

    private static func looksLikeCode(_ s: String) -> Bool {
        (s.contains("{") && s.contains("}")) || s.contains(";\n") || s.split(separator: "\n").count > 2
    }

    private static func guessLanguage(_ s: String) -> String {
        if s.contains("func ") || s.contains("var ") { return "swift" }
        if s.contains("=>") || s.contains("const ") { return "javascript" }
        if s.contains("def ") { return "python" }
        return "text"
    }
}
