import Foundation

/// Pure helpers for deciding when a recording session should continue after mic prep.
enum VoiceRecordingMicReadiness {
    /// Hold-to-talk should not keep recording if the user already released during mic prep.
    static func shouldStopImmediatelyAfterPrep(
        mode: VoiceActivationMode,
        isHotkeyHeld: Bool
    ) -> Bool {
        mode == .hold && !isHotkeyHeld
    }
}
