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
    /// Source transcript ID when this run is a history retry.
    let retrySourceTranscriptID: String?
    /// Wall-clock start of the operation. Used for total timing metrics.
    let operationStartedAt: Date
    /// When cleanup latency budget should start. Defaults to operation start; ASRPhase
    /// sets this after batch ASR so LLM cleanup is not penalized by inference time.
    var cleanupBudgetStartedAt: Date

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
    /// Live ASR finalize duration in milliseconds when live finish runs.
    var liveFinalizeMs: Int?
    /// Filled by PastePhase.
    var pasteResult: CursorPaster.Result?
    /// Cleanup duration in milliseconds.
    var cleanupMs: Int?
    /// Paste duration in milliseconds.
    var pasteMs: Int?
    /// New transcript row produced by PastePhase after saving.
    var savedTranscript: VoiceTranscript?
    /// Pipeline stage that failed for this run.
    var failedStage: VoiceTranscriptFailedStage?
    /// Standardized machine-readable failure reason.
    var failureReason: String?

    init(
        captured: CapturedAudio,
        presetASRResult: VoiceTranscriptionResult?,
        appBundleID: String?,
        generation: Int,
        retrySourceTranscriptID: String? = nil,
        operationStartedAt: Date
    ) {
        self.captured = captured
        self.presetASRResult = presetASRResult
        self.appBundleID = appBundleID
        self.generation = generation
        self.retrySourceTranscriptID = retrySourceTranscriptID
        self.operationStartedAt = operationStartedAt
        self.cleanupBudgetStartedAt = operationStartedAt
    }
}
