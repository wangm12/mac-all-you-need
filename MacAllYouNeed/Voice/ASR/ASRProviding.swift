import Core
import Foundation

/// Protocol that all ASR engine implementations must satisfy.
///
/// Engines are selected polymorphically via `VoiceCoordinator.activeEngine`; no
/// call-site branching on concrete type is required for transcription.
/// Warmup helpers that are engine-specific (e.g. `VoiceLocalASREngine.warmup`)
/// are not part of this protocol because they are lifecycle concerns, not
/// transcription concerns.
protocol ASRProviding: Sendable {
    /// A stable string that identifies the engine and model in transcripts
    /// and metrics. Examples: `"qwen3-0.5b"`, `"groq-whisper-large-v3-turbo"`.
    var modelIdentifier: String { get }

    /// Transcribe raw PCM samples and return the recognised text.
    ///
    /// - Parameters:
    ///   - samples: Mono Float32 samples at `sampleRate` Hz.
    ///   - sampleRate: Native sample rate of `samples` (engines resample internally).
    ///   - options: Transcription options; pass `.default` when no override is needed.
    func transcribe(
        samples: [Float],
        sampleRate: Double,
        options: VoiceTranscriptionOptions
    ) async throws -> VoiceTranscriptionResult
}
