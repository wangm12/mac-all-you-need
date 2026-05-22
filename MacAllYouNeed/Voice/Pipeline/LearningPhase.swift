import Core
import Foundation

/// Phase 4 of the voice pipeline. Fires the post-edit learning monitor as
/// fire-and-forget after a successful paste. The actual monitoring logic
/// lives in `VoicePostEditLearningMonitor`; this phase just decides whether
/// to start it and bundles the arguments. Tests can inject a no-op closure
/// to verify it gets called without spinning up the real monitor.
@MainActor
struct LearningPhase {
    /// Closure that actually starts the monitor. Production wires this to
    /// `VoiceCoordinator.startLearningMonitor(pastedText:transcriptID:appBundleID:isAutoSubmit:snapshot:)`.
    let start: (
        _ pastedText: String,
        _ transcriptID: String?,
        _ appBundleID: String?,
        _ isAutoSubmit: Bool,
        _ snapshot: AXTargetSnapshot?
    ) -> Void

    func run(_ ctx: VoicePipelineContext) {
        guard let cleanupResult = ctx.cleanupResult,
              let saved = ctx.savedTranscript
        else { return }
        start(
            cleanupResult.cleanedText,
            saved.id,
            ctx.appBundleID,
            false,
            ctx.axSnapshot
        )
    }
}
