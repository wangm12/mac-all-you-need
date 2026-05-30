import Foundation

public enum SmartTextService {
    public static func calculate(_ raw: String) -> CalculationResult? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count <= 256, !s.isEmpty else { return nil }
        if let det = try? NSDataDetector(types:
            NSTextCheckingResult.CheckingType.phoneNumber.rawValue |
            NSTextCheckingResult.CheckingType.date.rawValue),
           det.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil { return nil }
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/%^() ,")
        guard s.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        let normalized = s.replacingOccurrences(of: ",", with: "")
        // Require at least one binary operator with operands on both sides so a
        // bare number ("42") is not treated as a calculation.
        guard normalized.range(of: #"\d\s*[-+*/%^]"#, options: .regularExpression) != nil,
              normalized.range(of: #"[-+*/%^]\s*[\d(]"#, options: .regularExpression) != nil else { return nil }
        guard let d = ExpressionEvaluator.evaluate(normalized), d.isFinite else { return nil }
        let value = (d == d.rounded()) ? String(Int(d)) : String(d)
        return CalculationResult(expression: s, value: value)
    }
}

/// Small recursive-descent arithmetic evaluator. Used instead of NSExpression
/// because NSExpression(format:) does not support the `^` power operator and
/// throws on malformed input rather than returning nil.
enum ExpressionEvaluator {
    static func evaluate(_ input: String) -> Double? {
        var parser = Parser(input)
        guard let value = parser.parseExpression(), parser.isAtEnd else { return nil }
        return value
    }

    private struct Parser {
        private let chars: [Character]
        private var index = 0
        init(_ s: String) { chars = Array(s) }

        var isAtEnd: Bool {
            var i = index
            while i < chars.count, chars[i] == " " { i += 1 }
            return i >= chars.count
        }

        private mutating func skipSpaces() {
            while index < chars.count, chars[index] == " " { index += 1 }
        }

        private func peek() -> Character? {
            var i = index
            while i < chars.count, chars[i] == " " { i += 1 }
            return i < chars.count ? chars[i] : nil
        }

        private mutating func consume(_ c: Character) -> Bool {
            skipSpaces()
            if index < chars.count, chars[index] == c { index += 1; return true }
            return false
        }

        // expression := term (('+' | '-') term)*
        mutating func parseExpression() -> Double? {
            guard var left = parseTerm() else { return nil }
            while let op = peek(), op == "+" || op == "-" {
                _ = consume(op)
                guard let right = parseTerm() else { return nil }
                left = op == "+" ? left + right : left - right
            }
            return left
        }

        // term := factor (('*' | '/' | '%') factor)*
        private mutating func parseTerm() -> Double? {
            guard var left = parseFactor() else { return nil }
            while let op = peek(), op == "*" || op == "/" || op == "%" {
                _ = consume(op)
                guard let right = parseFactor() else { return nil }
                switch op {
                case "*": left *= right
                case "/":
                    if right == 0 { return .infinity }
                    left /= right
                default:
                    if right == 0 { return .infinity }
                    left = left.truncatingRemainder(dividingBy: right)
                }
            }
            return left
        }

        // factor := base ('^' factor)?   (right-associative power)
        private mutating func parseFactor() -> Double? {
            guard let base = parseUnary() else { return nil }
            if let op = peek(), op == "^" {
                _ = consume(op)
                guard let exp = parseFactor() else { return nil }
                return pow(base, exp)
            }
            return base
        }

        // unary := ('-' | '+')? primary
        private mutating func parseUnary() -> Double? {
            if let op = peek(), op == "-" || op == "+" {
                _ = consume(op)
                guard let v = parseUnary() else { return nil }
                return op == "-" ? -v : v
            }
            return parsePrimary()
        }

        // primary := number | '(' expression ')'
        private mutating func parsePrimary() -> Double? {
            skipSpaces()
            if consume("(") {
                guard let v = parseExpression(), consume(")") else { return nil }
                return v
            }
            var digits = ""
            while index < chars.count, chars[index].isNumber || chars[index] == "." {
                digits.append(chars[index]); index += 1
            }
            return digits.isEmpty ? nil : Double(digits)
        }
    }
}

extension SmartTextService {
    public static let trackingParameters: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "msclkid", "mc_eid", "mc_cid",
        "igshid", "si", "ref", "ref_src", "_hsenc", "_hsmi", "vero_id",
        "oly_enc_id", "oly_anon_id", "yclid", "twclid", "wickedid", "_openstat"
    ]
    public static func isTracking(_ key: String) -> Bool {
        let k = key.lowercased()
        return k.hasPrefix("utm_") || trackingParameters.contains(k)
    }
    public static func cleanLink(_ raw: String) -> LinkCleanResult? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.contains("\n"), !s.contains(" "),
              var comps = URLComponents(string: s),
              let scheme = comps.scheme, scheme == "http" || scheme == "https",
              comps.host != nil, let items = comps.queryItems, !items.isEmpty
        else { return nil }
        let kept = items.filter { !isTracking($0.name) }
        let removed = items.count - kept.count
        guard removed > 0 else { return nil }
        comps.queryItems = kept.isEmpty ? nil : kept
        guard let cleaned = comps.string else { return nil }
        return LinkCleanResult(cleaned: cleaned, removedCount: removed, original: s)
    }
}

extension SmartTextService {
    public static func detectCodeLanguage(in raw: String) -> CodeLanguage? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // A shebang is unambiguous shell; check before the markdown guard, which
        // would otherwise treat the leading "#!" line as a markdown heading.
        if s.hasPrefix("#!/") { return .shell }
        let lines = s.split(separator: "\n")
        let mdLines = lines.filter { $0.hasPrefix("#") || $0.hasPrefix("- ") || $0.hasPrefix("* ") }
        if !lines.isEmpty, mdLines.count * 2 >= lines.count, !s.contains("{") { return nil }
        if s.range(of: #"(?i)\bselect\b[\s\S]+\bfrom\b"#, options: .regularExpression) != nil { return .sql }
        if s.range(of: #"<[a-zA-Z][^>]*>[\s\S]*</[a-zA-Z]"#, options: .regularExpression) != nil { return .html }
        if s.contains("func ") || s.contains("let ") || s.contains("var ") || s.contains("guard ") { return .swift }
        if s.contains("=>") || s.contains("const ") || s.contains("function ") { return .javascript }
        if s.contains("def ") || (s.contains("import ") && s.contains(":")) { return .python }
        if s.contains("#include") { return .c }
        if s.contains("echo ") { return .shell }
        let braceDensity = (s.contains("{") && s.contains("}")) || s.contains(";\n")
        return braceDensity ? .unknown : nil
    }
}
