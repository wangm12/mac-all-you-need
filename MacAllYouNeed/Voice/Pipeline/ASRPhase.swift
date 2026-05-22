import Core
import Foundation
import OSLog

/// Phase 1 of the voice pipeline. Runs the ASR engine over the captured audio
/// and stores the result on the context. Honors the `presetASRResult`
/// fast-path used by the undo replay flow — when the user cancels mid-cleanup
/// we already have the ASR transcript and don't need to re-run it.
struct ASRPhase {
    let engine: any VoiceTranscriptionEngine
    let log: Logger

    /// Runs ASR (or skips it when `presetASRResult` was provided) and writes
    /// `asrResult` + `asrMs` back into `ctx`.
    func run(_ ctx: inout VoicePipelineContext) async throws {
        if let preset = ctx.presetASRResult {
            ctx.asrResult = preset
            ctx.asrMs = nil
            return
        }
        let asrStart = Date()
        let result = try await engine.transcribe(
            samples: ctx.captured.samples,
            sampleRate: ctx.captured.sampleRate,
            options: .default
        )
        let ms = Int(Date().timeIntervalSince(asrStart) * 1000)
        log.info("ASR done — \(ms, privacy: .public)ms model: \(result.modelIdentifier, privacy: .public) lang: \(result.language.rawValue, privacy: .public) chars: \(result.text.count, privacy: .public)")
        ctx.asrResult = result
        ctx.asrMs = ms
    }
}
