import Foundation

public struct VoiceDictionaryCSVRow: Equatable, Sendable {
    public let phrase: String
    public let replacement: String

    public init(phrase: String, replacement: String) {
        self.phrase = phrase
        self.replacement = replacement
    }
}

public enum VoiceDictionaryCSVParserError: Error, Equatable {
    case emptyFile
    case noValidRows
}

public enum VoiceDictionaryCSVImportError: Error, Equatable {
    case unsupportedEncoding
}

public enum VoiceDictionaryCSVParser {
    /// User-facing format description for the import sheet.
    public static let formatTitle = "CSV format"
    public static let formatSummary = """
        Save a UTF-8 CSV with two columns per row: the heard phrase, then the replacement. \
        An optional header row is supported.
        """

    public static let formatExample = """
        phrase,replacement
        海涛,江涛
        deploy service,Deploy
        "quoted, phrase","Quoted, fixed"
        """

    public static let formatRules: [String] = [
        "UTF-8 encoding (.csv or .txt)",
        "Column 1: heard phrase (what dictation often produces)",
        "Column 2: replacement (what to paste after cleanup)",
        "Optional header: phrase,replacement (or heard,replacement)",
        "Use quotes when a value contains commas",
        "Lines starting with # are ignored"
    ]

    public static func parse(_ text: String) throws -> [VoiceDictionaryCSVRow] {
        let trimmedFile = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFile.isEmpty else { throw VoiceDictionaryCSVParserError.emptyFile }

        var rows: [VoiceDictionaryCSVRow] = []
        var isFirstDataRow = true

        for line in trimmedFile.split(whereSeparator: \.isNewline) {
            let rawLine = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            if rawLine.isEmpty || rawLine.hasPrefix("#") { continue }

            let fields = parseCSVLine(rawLine)
            guard fields.count >= 2 else { continue }

            let phrase = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if phrase.isEmpty || replacement.isEmpty { continue }

            if isFirstDataRow, isHeaderRow(phrase: phrase, replacement: replacement) {
                isFirstDataRow = false
                continue
            }
            isFirstDataRow = false

            rows.append(.init(phrase: phrase, replacement: replacement))
        }

        guard !rows.isEmpty else { throw VoiceDictionaryCSVParserError.noValidRows }
        return rows
    }

    private static func isHeaderRow(phrase: String, replacement: String) -> Bool {
        let phraseKey = phrase.lowercased()
        let replacementKey = replacement.lowercased()
        let phraseHeaders: Set<String> = ["phrase", "heard", "from", "source", "misrecognition"]
        let replacementHeaders: Set<String> = ["replacement", "to", "target", "correct", "fixed"]
        return phraseHeaders.contains(phraseKey) && replacementHeaders.contains(replacementKey)
    }

    /// Minimal RFC 4180-style parser for a single CSV line.
    static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var index = line.startIndex

        while index < line.endIndex {
            let char = line[index]
            if char == "\"" {
                let next = line.index(after: index)
                if inQuotes, next < line.endIndex, line[next] == "\"" {
                    current.append("\"")
                    index = line.index(after: next)
                    continue
                }
                inQuotes.toggle()
                index = next
                continue
            }
            if char == ",", !inQuotes {
                fields.append(current)
                current = ""
                index = line.index(after: index)
                continue
            }
            current.append(char)
            index = line.index(after: index)
        }
        fields.append(current)
        return fields
    }
}

public struct VoiceDictionaryCSVImportSummary: Sendable, Equatable {
    public var imported: Int
    public var parseErrors: [String]

    public init(imported: Int = 0, parseErrors: [String] = []) {
        self.imported = imported
        self.parseErrors = parseErrors
    }
}
