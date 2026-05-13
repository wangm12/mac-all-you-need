import Foundation

enum FuzzyMatcher {
    static func rank(candidates: [String], query: String) -> [String] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return candidates }

        var scored: [(index: Int, score: Double)] = []
        for (index, candidate) in candidates.enumerated() {
            let normalizedCandidate = candidate.lowercased()
            let candidateTokens = tokens(in: normalizedCandidate)

            if normalizedCandidate == normalizedQuery {
                scored.append((index: index, score: 1200))
                continue
            }

            if candidateTokens.contains(normalizedQuery) {
                scored.append((index: index, score: 1150))
                continue
            }

            if normalizedCandidate.contains(normalizedQuery) {
                let startIndex = normalizedCandidate.range(of: normalizedQuery)?.lowerBound
                let offset = startIndex.map {
                    normalizedCandidate.distance(from: normalizedCandidate.startIndex, to: $0)
                } ?? 0
                let lengthPenalty = max(0, normalizedCandidate.count - normalizedQuery.count)
                scored.append((index: index, score: 1000 - Double(offset * 2 + lengthPenalty)))
                continue
            }

            if normalizedQuery.count <= 6 {
                let distance = bestShortDistance(
                    query: normalizedQuery,
                    candidate: normalizedCandidate,
                    tokens: candidateTokens
                )
                let threshold = max(2, normalizedQuery.count / 3)
                if let distance, distance <= threshold {
                    scored.append((index: index, score: 100 - Double(distance)))
                    continue
                }
            }

            let queryTrigrams = trigrams(normalizedQuery)
            let candidateTrigrams = trigrams(normalizedCandidate)
            let overlap = queryTrigrams.intersection(candidateTrigrams).count
            if overlap > 0 {
                scored.append((index: index, score: Double(overlap) / Double(queryTrigrams.count)))
            }
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.index < rhs.index }
                return lhs.score > rhs.score
            }
            .map { candidates[$0.index] }
    }

    private static func tokens(in text: String) -> [String] {
        text
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private static func bestShortDistance(query: String, candidate: String, tokens: [String]) -> Int? {
        let terms = (tokens.isEmpty ? [candidate] : tokens) + [candidate]
        return terms.compactMap { term -> Int? in
            guard !term.isEmpty else { return nil }
            let sameLengthPrefix = String(term.prefix(query.count))
            let nearLengthPrefix = String(term.prefix(min(term.count, query.count + 1)))
            return min(editDistance(query, sameLengthPrefix), editDistance(query, nearLengthPrefix))
        }.min()
    }

    private static func trigrams(_ text: String) -> Set<String> {
        guard text.count >= 3 else { return [text] }
        let characters = Array(text)
        var output: Set<String> = []
        for index in 0...(characters.count - 3) {
            output.insert(String(characters[index..<(index + 3)]))
        }
        return output
    }

    private static func editDistance(_ left: String, _ right: String) -> Int {
        let leftChars = Array(left)
        let rightChars = Array(right)
        if leftChars.isEmpty { return rightChars.count }
        if rightChars.isEmpty { return leftChars.count }

        var previous = Array(0...rightChars.count)
        var current = Array(repeating: 0, count: rightChars.count + 1)
        for i in 1...leftChars.count {
            current[0] = i
            for j in 1...rightChars.count {
                let cost = leftChars[i - 1] == rightChars[j - 1] ? 0 : 1
                current[j] = Swift.min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost
                )
            }
            swap(&previous, &current)
        }
        return previous[rightChars.count]
    }
}
