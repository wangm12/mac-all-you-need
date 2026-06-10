import Foundation

/// Shared segment sizing for Qwen3 long-form dictation (batch + live).
enum VoiceLongFormASRPlanning {
    /// Safe per-pass audio window for Qwen3 KV cache (~512 tokens).
    static let segmentSeconds: Double = 25.0
    /// Overlap between adjacent committed segments to improve merge quality.
    static let overlapSeconds: Double = 2.0
    static let sampleRate: Int = 16_000
    /// Output token budget per pass (512 cache minus prompt headroom).
    static let maxNewTokensPerPass = 448
    /// Minimum recording duration before a widened tail pass is considered.
    static let quickPassMinimumSeconds: Double = 14.0
    /// Tail context window for the final pass when prior segments were committed.
    static let quickPassWindowSeconds: Double = 18.0

    static var maxSegmentSamples: Int {
        Int(segmentSeconds * Double(sampleRate))
    }

    static var overlapSamples: Int {
        Int(overlapSeconds * Double(sampleRate))
    }

    static var quickPassWindowSamples: Int {
        Int(quickPassWindowSeconds * Double(sampleRate))
    }

    /// Samples to commit from the front of a pending buffer once it reaches `maxSegmentSamples`.
    static var commitLengthSamples: Int {
        max(maxSegmentSamples - overlapSamples, 1)
    }

    /// Returns how many front samples to commit, or nil if the buffer is not full enough.
    static func samplesToCommit(pendingCount: Int) -> Int? {
        guard pendingCount >= maxSegmentSamples else { return nil }
        return commitLengthSamples
    }

    /// Batch stride for offline chunking with overlap between consecutive windows.
    static var batchStrideSamples: Int {
        max(maxSegmentSamples - overlapSamples, 1)
    }

    struct TailPlan: Equatable {
        let useWidenedTail: Bool
        let tailSampleCount: Int
    }

    /// Chooses pending-only vs widened captured tail for the final live pass.
    static func tailTranscriptionPlan(
        totalCapturedCount: Int,
        capturedSampleRate: Double,
        committedPartCount: Int,
        pendingCount: Int
    ) -> TailPlan {
        let safeSampleRate = max(capturedSampleRate, 1)
        let durationSeconds = Double(totalCapturedCount) / safeSampleRate
        if committedPartCount > 0, durationSeconds >= quickPassMinimumSeconds {
            let widenedCount = min(quickPassWindowSamples, totalCapturedCount)
            return TailPlan(useWidenedTail: true, tailSampleCount: widenedCount)
        }
        return TailPlan(useWidenedTail: false, tailSampleCount: pendingCount)
    }
}

/// Guards widened-tail merges against duplicated middle text when ASR paraphrases overlap.
enum VoiceLongFormTailMergePolicy {
    private static let sharedWindowMinLength = 4

    static func shouldUseWidenedTailMerge(
        pendingTailText: String,
        widenedTailText: String,
        committedTextBeforeTail: String
    ) -> Bool {
        let widened = widenedTailText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !widened.isEmpty else { return false }

        let pending = pendingTailText.trimmingCharacters(in: .whitespacesAndNewlines)
        let committed = committedTextBeforeTail.trimmingCharacters(in: .whitespacesAndNewlines)

        if !committed.isEmpty {
            let widenedMergeResult = VoiceSequentialTranscriptMerge.merge(previous: committed, next: widened)
            if widenedMergeResult.overlapCount > 0 {
                return true
            }
            if hasSharedWindow(committed, widened, minLength: sharedWindowMinLength) {
                return false
            }
        }

        return true
    }

    private static func mergeCommitted(_ committed: String, tail: String) -> String {
        guard !committed.isEmpty else { return tail }
        guard !tail.isEmpty else { return committed }
        return VoiceSequentialTranscriptMerge.merge(previous: committed, next: tail).text
    }

    private static func hasSharedWindow(_ lhs: String, _ rhs: String, minLength: Int) -> Bool {
        guard min(lhs.count, rhs.count) >= minLength else { return false }
        let shorter = lhs.count <= rhs.count ? lhs : rhs
        let longer = lhs.count <= rhs.count ? rhs : lhs
        let chars = Array(shorter)
        let upperBound = chars.count - minLength
        guard upperBound >= 0 else { return false }

        for start in 0...upperBound {
            let window = String(chars[start..<(start + minLength)])
            if longer.contains(window) {
                return true
            }
        }
        return false
    }
}
