import Foundation

/// Single source of truth for all tunable voice pipeline constants.
/// Replace all scattered literals in the voice subsystem with references
/// to this struct. Load via `VoiceTuning.current` (reads from UserDefaults
/// with defaults, or use `.default` for the hardcoded baseline).
struct VoiceTuning {
    /// Minimum recording duration in seconds before ASR is attempted.
    /// Replaces the rate-dependent "> 800 samples" check.
    var minRecordingDurationSeconds: Double = 0.1

    /// Amplitude threshold for "has speech signal" classification.
    var speechPeakThreshold: Float = 0.02

    /// Ceiling for live-ASR session finalize (local engines).
    var liveFinalizeSecondsLocal: TimeInterval = 0.8

    /// Ceiling for live-ASR session finalize (cloud/realtime engines).
    var liveFinalizeSecondsRealtime: TimeInterval = 2.5

    /// Hard ceiling for LLM cleanup phase.
    var cleanupHardLimitSeconds: TimeInterval = 12.0

    /// Soft (balanced) budget for LLM cleanup before falling back to local text.
    var cleanupSoftBudgetSeconds: TimeInterval = 2.0

    /// Timeout for the paste phase.
    var pasteTimeoutSeconds: TimeInterval = 2.0

    /// How long the Undo affordance is shown after a cancel.
    var undoWindowSeconds: TimeInterval = 5.0

    /// Delay after Cmd+V before restoring clipboard.
    var clipboardRestoreMs: Int = 200

    /// Warmup timeout guard for local models.
    var warmupTimeoutSeconds: TimeInterval = 3.0

    static let `default` = VoiceTuning()
}
