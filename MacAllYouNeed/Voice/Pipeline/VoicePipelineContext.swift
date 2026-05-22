import Core
import Foundation

/// Mutable bag of inputs and outputs that flows through the five voice
/// pipeline phases (ASR → cleanup → paste → save → learning) inside
/// `VoiceCoordinator.processCapturedAudio`. Each phase reads what it needs
/// and writes its outputs back so the next phase can pick them up — no phase
/// reaches into the coordinator directly.
///
/// Designed as a struct so phases can take it as `inout` and pass-by-value
/// snapshotting works when a phase wants a stable view.
struct VoicePipelineContext {
    // MARK: Inputs (set by coordinator before the pipeline runs)

    /// The audio buffer captured by the mic for this dictation.
    let captured: CapturedAudio
    /// If non-nil, ASR has already run (undo replay path) and ASRPhase will
    /// just hand the result back through to CleanupPhase.
    let presetASRResult: VoiceTranscriptionResult?
    /// Frontmost app bundle ID at the start of this dictation.
    let appBundleID: String?
    /// Generation counter snapshot — coordinator uses this between phases to
    /// detect that a newer operation has superseded this one.
    let generation: Int
    /// Wall-clock start of the operation. Used for cleanup latency budget.
    let operationStartedAt: Date

    // MARK: Outputs (filled in by each phase as they run)

    /// Filled by ASRPhase. nil until ASR completes.
    var asrResult: VoiceTranscriptionResult?
    /// ASR duration in milliseconds. nil when ASR was skipped (undo replay).
    var asrMs: Int?
    /// Filled by CleanupPhase.
    var cleanupResult: VoiceCleanupResult?
    /// AX snapshot captured immediately before paste so the learning monitor
    /// can track the target field across paste latency.
    var axSnapshot: AXTargetSnapshot?
    /// Filled by PastePhase.
    var pasteResult: CursorPaster.Result?
    /// New transcript row produced by PastePhase after saving.
    var savedTranscript: VoiceTranscript?

    init(
        captured: CapturedAudio,
        presetASRResult: VoiceTranscriptionResult?,
        appBundleID: String?,
        generation: Int,
        operationStartedAt: Date
    ) {
        self.captured = captured
        self.presetASRResult = presetASRResult
        self.appBundleID = appBundleID
        self.generation = generation
        self.operationStartedAt = operationStartedAt
    }
}
