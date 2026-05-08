import Foundation

enum FuzzyMatcher {
    static func rank(candidates: [String], query: String) -> [String] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return candidates }

        var scored: [(index: Int, score: Double)] = []
        for (index, candidate) in candidates.enumerated() {
            let normalizedCandidate = candidate.lowercased()
            if normalizedCandidate.contains(normalizedQuery) {
                scored.append((index: index, score: 1000))
                continue
            }

            if normalizedQuery.count <= 6 {
                let limit = min(normalizedCandidate.count, max(8, normalizedQuery.count + 4))
                let prefix = String(normalizedCandidate.prefix(limit))
                let distance = editDistance(normalizedQuery, prefix)
                let threshold = max(1, normalizedQuery.count / 3)
                if distance <= threshold {
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
