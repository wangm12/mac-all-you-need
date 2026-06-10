import Core
import Foundation

/// Heuristics for deciding whether a live ASR finish result should fall back to batch.
enum VoiceLiveASRQualityCheck {
    static func looksSuspicious(result: VoiceTranscriptionResult, captured: CapturedAudio) -> Bool {
        let duration = captured.endedAt.timeIntervalSince(captured.startedAt)
        let chars = result.text.count
        guard duration >= 3 else { return false }
        if Double(chars) / duration < 0.5 { return true }
        if captured.peakLevel > 0.02, chars < 2 { return true }
        return false
    }
}
