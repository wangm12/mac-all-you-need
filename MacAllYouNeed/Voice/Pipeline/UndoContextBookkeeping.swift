import Core
import Foundation

/// Phase 5 of the voice pipeline. Holds the captured audio + ASR result
/// captured during the in-flight operation so a mid-stream cancel can offer
/// "Undo" for 5 seconds without forcing the user to re-dictate.
///
/// Two related responsibilities:
///   1. **Inflight bookkeeping** — `update(captured:appBundleID:asrResult:)`
///      is called at the start of `processCapturedAudio` and after ASR
///      completes so the cancel handler always has the most recent snapshot.
///   2. **Pending undo state** — when the user cancels, `recordCancel(...)`
///      stashes a snapshot. `consumePendingUndo()` is called by the Undo
///      button to replay it. `expirePendingUndo()` is called after the 5s
///      window or when the user explicitly dismisses the cancelled pill.
///
/// Kept as a small reference type (rather than a struct) so the coordinator
/// can hand callbacks into it without copy semantics surprising us.
@MainActor
final class UndoContextBookkeeping {
    /// Snapshot kept after cancel so the user can tap Undo to replay it.
    struct Pending {
        let captured: CapturedAudio
        let asrResult: VoiceTranscriptionResult?
        let appBundleID: String?
        let cancelledAt: Date
    }

    /// Captured audio for the in-flight transcription. Held while
    /// .transcribing is active so a mid-stream cancel can offer Undo.
    private(set) var inflightCaptured: CapturedAudio?
    /// ASR result for the in-flight cleanup phase. Set after ASR completes so
    /// Undo during LLM cleanup can skip ASR and re-run only cleanup.
    private(set) var inflightASRResult: VoiceTranscriptionResult?
    /// Bundle ID of the frontmost app when this dictation began.
    private(set) var inflightAppBundleID: String?

    /// Snapshot kept after cancel. nil unless the user just cancelled and
    /// the 5-second window is still open.
    private(set) var pendingUndo: Pending?

    /// Replace the in-flight context. `asrResult` is the value as of right
    /// now — pass nil if ASR has not run yet.
    func setInflight(
        captured: CapturedAudio?,
        appBundleID: String?,
        asrResult: VoiceTranscriptionResult?
    ) {
        inflightCaptured = captured
        inflightAppBundleID = appBundleID
        inflightASRResult = asrResult
    }

    /// Update just the ASR result after the ASR phase completes. Leaves the
    /// other inflight fields untouched.
    func setInflightASRResult(_ result: VoiceTranscriptionResult?) {
        inflightASRResult = result
    }

    func clearInflight() {
        inflightCaptured = nil
        inflightASRResult = nil
        inflightAppBundleID = nil
    }

    /// Snapshot the current inflight context as a pending undo. Call from
    /// the cancel handler. Returns the recorded pending so callers can read
    /// the same value without a separate getter race.
    @discardableResult
    func recordCancel(
        captured: CapturedAudio,
        asrResult: VoiceTranscriptionResult?,
        appBundleID: String?
    ) -> Pending {
        let pending = Pending(
            captured: captured,
            asrResult: asrResult,
            appBundleID: appBundleID,
            cancelledAt: Date()
        )
        pendingUndo = pending
        return pending
    }

    /// Hand the pending undo out and clear it. Returns nil when no undo is
    /// pending. Coordinator passes this back into `processCapturedAudio` as
    /// the preset path.
    func consumePendingUndo() -> Pending? {
        let pending = pendingUndo
        pendingUndo = nil
        return pending
    }

    /// Explicitly drop the pending undo. Coordinator calls this when the 5s
    /// window expires or the user dismisses the cancelled pill.
    func expirePendingUndo() {
        pendingUndo = nil
    }

    /// True when an undo replay is still available to the user.
    var hasPendingUndo: Bool { pendingUndo != nil }
}
