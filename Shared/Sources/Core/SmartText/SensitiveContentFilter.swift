import Foundation

public enum SkipReason: String, Equatable, Sendable { case paymentCard, sensitiveWindow, concealed }

public enum SensitiveContentFilter {
    static let titleKeywords = ["password", "1password", "keychain", "bitwarden", "lastpass",
                                "secret", "private key", "seed phrase", "cvv", "social security"]
    public static func shouldSkip(text: String, windowTitle: String?, pasteboardTypes: [String]) -> SkipReason? {
        if pasteboardTypes.contains("org.nspasteboard.ConcealedType") { return .concealed }
        if let t = windowTitle?.lowercased(), titleKeywords.contains(where: t.contains) { return .sensitiveWindow }
        if containsLuhnRun(text) { return .paymentCard }
        return nil
    }

    static func containsLuhnRun(_ text: String) -> Bool {
        let stripped = text.replacingOccurrences(of: "[ -]", with: "", options: .regularExpression)
        for match in stripped.ranges(of: #"\d{13,19}"#) {
            if luhnValid(String(stripped[match])) { return true }
        }
        return false
    }

    static func luhnValid(_ digits: String) -> Bool {
        let nums = digits.compactMap(\.wholeNumberValue)
        guard nums.count >= 13 else { return false }
        var sum = 0
        for (i, d) in nums.reversed().enumerated() {
            var v = d
            if i % 2 == 1 { v *= 2; if v > 9 { v -= 9 } }
            sum += v
        }
        return sum % 10 == 0
    }
}

private extension String {
    func ranges(of pattern: String) -> [Range<String.Index>] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = NSRange(startIndex..., in: self)
        return re.matches(in: self, range: ns).compactMap { Range($0.range, in: self) }
    }
}
