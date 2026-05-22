import Core
import Foundation
import OSLog

/// Phase 2 of the voice pipeline. Builds the personalization-enriched cleanup
/// request from the raw ASR text, runs the cleanup pipeline (LLM or local
/// fallback), and writes the timed `VoiceCleanupResult` back onto the
/// context.
@MainActor
struct CleanupPhase {
    /// Snapshot of the personalization context resolved for this dictation.
    /// The phase only reads it; resolution is the coordinator's job.
    struct PersonalizationInputs {
        let dictionaryEntries: [VoiceDictionaryEntry]
        let appContext: VoicePersonalizationContext?
        let globalContext: VoicePersonalizationContext?
        let recentExamples: [(before: String, after: String)]
    }

    let makePipeline: (TimeInterval) -> VoiceCleanupPipeline
    let personalization: PersonalizationInputs
    /// Optional spy invoked with the resolved request just before the
    /// pipeline runs. Tests use this to assert what the LLM would have been
    /// asked. Production wires nil so this is a no-op.
    let observer: ((VoiceCleanupRequest) -> Void)?
    let log: Logger

    func run(_ ctx: inout VoicePipelineContext) async {
        guard let asrResult = ctx.asrResult else { return }
        let cleanupRequest = VoiceCoordinator.buildCleanupRequest(
            rawText: asrResult.text,
            appBundleID: ctx.appBundleID,
            language: asrResult.language,
            dictionaryEntries: personalization.dictionaryEntries,
            appContext: personalization.appContext,
            globalContext: personalization.globalContext,
            recentExamples: personalization.recentExamples
        )
        observer?(cleanupRequest)

        let elapsedBeforeCleanup = Date().timeIntervalSince(ctx.operationStartedAt)
        let pipeline = makePipeline(elapsedBeforeCleanup)
        log.info("LLM cleanup start — text length: \(asrResult.text.count, privacy: .public) chars")
        let cleanupStart = Date()
        let raw = await pipeline.clean(cleanupRequest)
        let cleanupMs = Int(Date().timeIntervalSince(cleanupStart) * 1000)
        let totalMs = Int(Date().timeIntervalSince(ctx.operationStartedAt) * 1000)
        let timed = raw.withTimings(
            asrMs: ctx.asrMs,
            cleanupMs: cleanupMs,
            totalMs: totalMs
        )
        log.info("LLM cleanup done — \(cleanupMs, privacy: .public)ms total: \(totalMs, privacy: .public)ms usedLLM: \(timed.usedLLM, privacy: .public) provider: \(timed.providerIdentifier ?? "none", privacy: .public) chars: \(timed.cleanedText.count, privacy: .public) fallback: \(timed.fallbackReason?.rawValue ?? "none", privacy: .public)")
        ctx.cleanupResult = timed
    }
}
