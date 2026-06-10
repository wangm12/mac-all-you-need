import Foundation

/// Merges sequential ASR chunk transcripts by removing suffix/prefix overlap.
/// Rules aligned with voxt `MLXTranscriptionPlanning.sequentialTranscriptMergeResult`.
enum VoiceSequentialTranscriptMerge {
    struct Result: Equatable {
        let text: String
        let overlapCount: Int
    }

    static func merge(previous: String, next: String) -> Result {
        let left = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = next.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty else { return Result(text: right, overlapCount: 0) }
        guard !right.isEmpty else { return Result(text: left, overlapCount: 0) }

        if left.hasSuffix(right) {
            return Result(text: left, overlapCount: right.count)
        }
        if right.hasPrefix(left) {
            return Result(text: right, overlapCount: left.count)
        }

        let leftLast = left.unicodeScalars.last
        let rightFirst = right.unicodeScalars.first
        let minimumOverlapCount: Int
        if let leftLast, let rightFirst,
           CharacterSet.alphanumerics.contains(leftLast),
           CharacterSet.alphanumerics.contains(rightFirst)
        {
            minimumOverlapCount = 3
        } else {
            minimumOverlapCount = 2
        }

        let overlapCount = suffixPrefixOverlapCount(left, right)
        if overlapCount >= minimumOverlapCount {
            let rightChars = Array(right)
            return Result(
                text: left + String(rightChars.dropFirst(overlapCount)),
                overlapCount: overlapCount
            )
        }

        let shouldInsertSpace: Bool
        if let leftLast, let rightFirst {
            shouldInsertSpace =
                CharacterSet.alphanumerics.contains(leftLast) &&
                CharacterSet.alphanumerics.contains(rightFirst)
        } else {
            shouldInsertSpace = true
        }
        let joined = shouldInsertSpace ? "\(left) \(right)" : left + right
        return Result(text: joined, overlapCount: 0)
    }

    static func mergeSequential(_ parts: [String]) -> String {
        var merged = ""
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if merged.isEmpty {
                merged = trimmed
            } else {
                merged = merge(previous: merged, next: trimmed).text
            }
        }
        return merged
    }

    private static func suffixPrefixOverlapCount(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        let maxOverlap = min(left.count, right.count)

        for overlap in stride(from: maxOverlap, through: 1, by: -1) {
            if Array(left.suffix(overlap)) == Array(right.prefix(overlap)) {
                return overlap
            }
        }
        return 0
    }
}
