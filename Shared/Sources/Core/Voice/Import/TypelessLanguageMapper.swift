import Foundation

public enum TypelessLanguageMapper {
    public static let typelessImportModelIdentifier = "typeless-import"

    public static func map(detectedLanguage: String?, languagesJSON: String?) -> VoiceLanguage {
        var tokens: [String] = []
        if let detected = normalizedToken(detectedLanguage) {
            tokens.append(detected)
        }
        tokens.append(contentsOf: tokensFromLanguagesJSON(languagesJSON))

        let hasChinese = tokens.contains(where: isChineseToken)
        let hasEnglish = tokens.contains(where: isEnglishToken)

        if hasChinese, hasEnglish { return .mixed }
        if hasChinese { return .chinese }
        if hasEnglish { return .english }
        return .unknown
    }

    private static func normalizedToken(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func tokensFromLanguagesJSON(_ json: String?) -> [String] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        if let array = try? JSONDecoder().decode([String].self, from: data) {
            return array.compactMap(normalizedToken)
        }
        if let object = try? JSONDecoder().decode([String: String].self, from: data) {
            return object.values.compactMap(normalizedToken)
        }
        return []
    }

    private static func isChineseToken(_ token: String) -> Bool {
        token.hasPrefix("zh") || token.contains("chinese") || token.contains("mandarin") || token == "cmn"
    }

    private static func isEnglishToken(_ token: String) -> Bool {
        token.hasPrefix("en") || token.contains("english")
    }
}
