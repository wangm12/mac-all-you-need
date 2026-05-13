import Foundation

enum VoiceLocalTextCleaner {
    static func clean(_ text: String) -> String {
        removeStandaloneFillers(from: normalizeSpokenDigitSequences(in: text))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeSpokenDigitSequences(in text: String) -> String {
        let characters = Array(text)
        var result = ""
        var index = 0

        while index < characters.count {
            guard let digit = digitValue(for: characters[index]) else {
                result.append(characters[index])
                index += 1
                continue
            }

            let start = index
            var digits = String(digit)
            index += 1
            while index < characters.count, let nextDigit = digitValue(for: characters[index]) {
                digits.append(nextDigit)
                index += 1
            }

            if digits.count >= 2, shouldNormalizeDigitRun(characters: characters, start: start, end: index) {
                result.append(digits)
            } else {
                result.append(String(characters[start ..< index]))
            }
        }

        return result
    }

    private static func shouldNormalizeDigitRun(characters: [Character], start: Int, end: Int) -> Bool {
        if start > 0, disallowedBeforeDigitRun.contains(characters[start - 1]) {
            return false
        }
        if end < characters.count, disallowedAfterDigitRun.contains(characters[end]) {
            return false
        }
        return true
    }

    private static func digitValue(for character: Character) -> Character? {
        switch character {
        case "零", "〇", "○": "0"
        case "一": "1"
        case "二", "两": "2"
        case "三": "3"
        case "四": "4"
        case "五": "5"
        case "六": "6"
        case "七": "7"
        case "八": "8"
        case "九": "9"
        default: nil
        }
    }

    private static func removeStandaloneFillers(from text: String) -> String {
        var result = ""
        var phrase = ""

        for character in text {
            if delimiters.contains(character) {
                appendNonFillerPhrase(phrase, delimiter: character, to: &result)
                phrase.removeAll(keepingCapacity: true)
            } else {
                phrase.append(character)
            }
        }

        appendNonFillerPhrase(phrase, delimiter: nil, to: &result)
        return result
    }

    private static func appendNonFillerPhrase(_ phrase: String, delimiter: Character?, to result: inout String) {
        let phrase = removingBoundaryFillers(from: phrase)
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isFiller(trimmed) else { return }
        guard !trimmed.isEmpty else { return }

        if result.isEmpty {
            result.append(trimmed)
        } else {
            result.append(phrase)
        }
        if let delimiter {
            result.append(delimiter)
        }
    }

    private static func isFiller(_ phrase: String) -> Bool {
        fillers.contains(phrase.lowercased())
    }

    private static func removingBoundaryFillers(from phrase: String) -> String {
        var characters = Array(phrase)

        while let firstFillerIndex = characters.firstIndex(where: { !$0.isWhitespace }) {
            guard chineseFillers.contains(characters[firstFillerIndex]) else { break }
            characters.removeSubrange(...firstFillerIndex)
        }

        while let lastFillerIndex = characters.lastIndex(where: { !$0.isWhitespace }) {
            guard chineseFillers.contains(characters[lastFillerIndex]) else { break }
            characters.removeSubrange(lastFillerIndex...)
        }

        return String(characters)
    }

    private static let fillers: Set<String> = [
        "嗯",
        "啊",
        "呃",
        "额",
        "em",
        "er",
        "uh",
        "um"
    ]

    private static let chineseFillers: Set<Character> = [
        "嗯",
        "啊",
        "呃",
        "额"
    ]

    private static let delimiters: Set<Character> = [
        "，", ",", "。", ".", "、", "！", "!", "？", "?"
    ]

    private static let disallowedBeforeDigitRun: Set<Character> = [
        "第"
    ]

    private static let disallowedAfterDigitRun: Set<Character> = [
        "年", "月", "日", "号", "点", "线"
    ]
}
