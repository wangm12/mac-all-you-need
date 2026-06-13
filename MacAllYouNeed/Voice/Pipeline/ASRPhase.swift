import Core
import Foundation
import OSLog

/// Phase 1 of the voice pipeline. Runs the ASR engine over the captured audio
/// and stores the result on the context. Honors the `presetASRResult`
/// fast-path used by the undo replay flow — when the user cancels mid-cleanup
/// we already have the ASR transcript and don't need to re-run it.
struct ASRPhase {
    let engine: (any ASRProviding)?
    let log: Logger

    /// Runs ASR (or skips it when `presetASRResult` was provided) and writes
    /// `asrResult` + `asrMs` back into `ctx`.
    func run(_ ctx: inout VoicePipelineContext) async throws {
        if let preset = ctx.presetASRResult {
            ctx.asrResult = preset
            ctx.asrMs = nil
            return
        }
        guard let engine else {
            throw ASRPhaseError.engineUnavailable
        }
        let asrStart = Date()
        var result = try await engine.transcribe(
            samples: ctx.captured.samples,
            sampleRate: ctx.captured.sampleRate,
            options: .default
        )
        let ms = Int(Date().timeIntervalSince(asrStart) * 1000)
        var trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let capturedPeak = ctx.captured.peakLevel
        let capturedDuration = ctx.captured.endedAt.timeIntervalSince(ctx.captured.startedAt)
        let hasSpeechSignal = capturedDuration >= 1.0 && capturedPeak >= 0.02
        if trimmed.isEmpty {
            if hasSpeechSignal {
                log.warning(
                    "ASR empty_with_signal — retrying once model: \(result.modelIdentifier, privacy: .public) duration: \(capturedDuration, privacy: .public)s peak: \(capturedPeak, privacy: .public)"
                )
                result = try await engine.transcribe(
                    samples: ctx.captured.samples,
                    sampleRate: ctx.captured.sampleRate,
                    options: .default
                )
                trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if trimmed.isEmpty {
            if hasSpeechSignal {
                log.error(
                    "ASR empty_with_signal — model: \(result.modelIdentifier, privacy: .public) lang: \(result.language.rawValue, privacy: .public) duration: \(capturedDuration, privacy: .public)s peak: \(capturedPeak, privacy: .public)"
                )
            } else {
                log.info(
                    "ASR empty_no_signal — model: \(result.modelIdentifier, privacy: .public) duration: \(capturedDuration, privacy: .public)s peak: \(capturedPeak, privacy: .public)"
                )
            }
        }
        log.info("ASR done — \(ms, privacy: .public)ms model: \(result.modelIdentifier, privacy: .public) lang: \(result.language.rawValue, privacy: .public) chars: \(result.text.count, privacy: .public)")
        ctx.asrResult = result
        ctx.asrMs = ms
        ctx.cleanupBudgetStartedAt = Date()
    }
}

enum ASRPhaseError: LocalizedError {
    case engineUnavailable

    var errorDescription: String? {
        "No ASR engine is configured. Select a recognition provider in Voice Settings."
    }
}
