import Foundation

/// Ranks folder-history rows for the hotkey search field (autojump-inspired token matching).
public enum FolderHistoryMatcher {
    /// Returns rows matching all query tokens, sorted by visit frequency then recency.
    public static func ranked(rows: [FolderHistoryRow], query: String) -> [FolderHistoryRow] {
        let tokens = tokenize(query)
        guard !tokens.isEmpty else { return rows }

        let ignoreCase = !tokens.contains(where: containsUppercase)

        return rows
            .filter { matches(path: $0.path, displayName: $0.displayName, tokens: tokens, ignoreCase: ignoreCase) }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
                if lhs.visitCount != rhs.visitCount { return lhs.visitCount > rhs.visitCount }
                return lhs.visitedAt > rhs.visitedAt
            }
    }

    private static func tokenize(_ query: String) -> [String] {
        query
            .split(whereSeparator: { $0.isWhitespace || $0 == "/" })
            .map { String($0) }
            .filter { !$0.isEmpty }
    }

    private static func matches(
        path: String,
        displayName: String,
        tokens: [String],
        ignoreCase: Bool
    ) -> Bool {
        let haystack = ignoreCase ? path.lowercased() + " " + displayName.lowercased() : path + " " + displayName
        return tokens.allSatisfy { token in
            let needle = ignoreCase ? token.lowercased() : token
            return haystack.contains(needle)
        }
    }

    private static func containsUppercase(_ string: String) -> Bool {
        string.unicodeScalars.contains { CharacterSet.uppercaseLetters.contains($0) }
    }
}
