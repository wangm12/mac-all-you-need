import Core
import Foundation
import OSLog

/// Phase 3 of the voice pipeline. Snapshots the AX focus target for the
/// learning monitor, paste the cleaned text via `CursorPaster`, then persists
/// the transcript + training example. Writes `axSnapshot`, `pasteResult`,
/// and `savedTranscript` back into the context.
@MainActor
struct PastePhase {
    /// Saves the transcript draft to the store and returns the persisted row.
    /// Throws to bubble up store failures (e.g. write contention).
    let saveTranscript: (
        _ transcriptID: String,
        _ captured: CapturedAudio,
        _ result: VoiceTranscriptionResult,
        _ cleanedText: String,
        _ appBundleID: String?,
        _ audioPath: String?,
        _ status: VoiceTranscriptStatus,
        _ failedStage: VoiceTranscriptFailedStage?,
        _ failureReason: String?,
        _ retrySourceTranscriptID: String?
    ) throws -> VoiceTranscript

    /// Encrypts + persists the captured audio. Returns nil when the user has
    /// not opted into audio retention. Fire-and-forget on failure.
    let persistAudio: (_ captured: CapturedAudio, _ transcriptID: String, _ forceSave: Bool) -> String?

    /// Saves the corresponding training example row when personalization is
    /// enabled. No-op when the user has opted out.
    let saveTrainingExample: (
        _ captured: CapturedAudio,
        _ result: VoiceTranscriptionResult,
        _ cleanedText: String,
        _ transcriptID: String,
        _ appBundleID: String?,
        _ audioPath: String?
    ) -> Void

    /// Performs the actual paste. Defaults to `CursorPaster.paste` in
    /// production; tests can inject a stub.
    let paste: (_ text: String, _ preferredTarget: AXTargetSnapshot?) async -> CursorPaster.Result

    /// AX snapshot reader. Defaults to `AXFocusedTextReader.snapshotFocused`.
    let snapshotFocused: () -> AXTargetSnapshot?

    let log: Logger

    func run(_ ctx: inout VoicePipelineContext) async throws {
        guard let asrResult = ctx.asrResult,
              let cleanupResult = ctx.cleanupResult
        else { return }
        let text = cleanupResult.cleanedText

        // Snapshot AX target BEFORE paste so the learning monitor can track
        // the field across paste latency even if the user switched apps.
        let axSnapshot = snapshotFocused()
        ctx.axSnapshot = axSnapshot

        let pasteResult = await paste(text, axSnapshot)
        log.info(
            "paste — path: \(pasteResult.deliveryPath.rawValue, privacy: .public) failure: \(pasteResult.failureReason?.rawValue ?? "none", privacy: .public) chars: \(text.count, privacy: .public)"
        )
        ctx.pasteResult = pasteResult
        let status: VoiceTranscriptStatus = pasteResult.insertedIntoActiveInput ? .success : .failed
        let failedStage: VoiceTranscriptFailedStage? = pasteResult.insertedIntoActiveInput ? nil : .paste
        let failureReason: String? = pasteResult.insertedIntoActiveInput
            ? nil
            : "paste_\(pasteResult.failureReason?.rawValue ?? "unknown")"

        let transcriptID = UUID().uuidString
        let audioPath = persistAudio(ctx.captured, transcriptID, !pasteResult.insertedIntoActiveInput)
        let saved = try saveTranscript(
            transcriptID,
            ctx.captured,
            asrResult,
            text,
            ctx.appBundleID,
            audioPath,
            status,
            failedStage,
            failureReason,
            ctx.retrySourceTranscriptID
        )
        log.info("transcript saved — id: \(saved.id, privacy: .public) audioPath: \(audioPath ?? "nil", privacy: .public)")
        ctx.savedTranscript = saved

        if pasteResult.insertedIntoActiveInput {
            saveTrainingExample(
                ctx.captured,
                asrResult,
                text,
                saved.id,
                ctx.appBundleID,
                audioPath
            )
        }
        NotificationCenter.default.post(name: .voiceTranscriptAppended, object: saved.id)
    }
}
