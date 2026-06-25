import Foundation

enum WindowHubFuzzyMatcher {
    static func score(query: String, candidate: String) -> Int? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return 0 }
        let c = candidate.lowercased()
        if c == q { return 1000 }
        if c.hasPrefix(q) { return 800 + q.count }
        if c.contains(q) { return 500 + q.count }
        return fuzzySubsequenceScore(query: q, candidate: c)
    }

    static func filter(targets: [WindowHubTarget], query: String) -> [WindowHubTarget] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return targets }
        return targets
            .compactMap { target -> (WindowHubTarget, Int)? in
                let fields = [
                    target.appName,
                    target.windowTitle,
                    target.tabTitle,
                    target.domain,
                    target.breadcrumb,
                ].compactMap { $0 }
                let best = fields.compactMap { score(query: q, candidate: $0) }.max() ?? 0
                return best > 0 ? (target, best) : nil
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private static func fuzzySubsequenceScore(query: String, candidate: String) -> Int? {
        var qi = query.startIndex
        var score = 0
        var lastMatch: String.Index?
        for ci in candidate.indices {
            guard qi < query.endIndex else { break }
            if candidate[ci] == query[qi] {
                if let last = lastMatch, candidate.index(after: last) == ci {
                    score += 4
                } else {
                    score += 2
                }
                lastMatch = ci
                qi = query.index(after: qi)
            }
        }
        guard qi == query.endIndex else { return nil }
        return 100 + score
    }
}
