import Core
import Foundation

/// Pure, testable decision tree for recording start.
/// Determines which ASR engine mode to use (streaming or batch) and whether
/// to start at all, based on configured provider, key presence, and network state.
///
/// No side effects — call `resolve(...)` with current state and act on the result.
enum VoiceRecordingStartPlanner {

    enum Decision: Equatable {
        case start(provider: VoiceASRProviderKind, mode: ASRMode)
        case blocked(BlockReason)
    }

    enum ASRMode: Equatable {
        case streaming   // live session with partial callbacks
        case batch       // full-audio → transcribe
    }

    enum BlockReason: Equatable {
        case localModelNotInstalled
        case micPermissionDenied

        var userMessage: String {
            switch self {
            case .localModelNotInstalled:
                "No ASR model installed. Download a model from Voice → Models before dictating."
            case .micPermissionDenied:
                "Microphone permission is required for voice dictation."
            }
        }
    }

    /// Resolve which engine and mode to use.
    ///
    /// - Parameters:
    ///   - configured: Currently selected provider kind.
    ///   - cloudKeyPresent: Whether a valid API key exists for the configured cloud provider.
    ///   - isOnline: Current network reachability.
    ///   - localModelInstalled: Whether the configured local model is downloaded and ready.
    ///   - localEngineCapabilities: Capabilities of the available local engine.
    static func resolve(
        configured: VoiceASRProviderKind,
        cloudKeyPresent: Bool,
        isOnline: Bool,
        localModelInstalled: Bool,
        localEngineCapabilities: VoiceASRCapabilities
    ) -> Decision {
        switch configured {
        case .local:
            // Local-only path.
            guard localModelInstalled else { return .blocked(.localModelNotInstalled) }
            let mode: ASRMode = localEngineCapabilities.supportsStreaming ? .streaming : .batch
            return .start(provider: .local, mode: mode)

        case .groq, .openAITranscribe, .elevenLabs, .deepgram:
            // Cloud provider configured — use it if conditions allow.
            if cloudKeyPresent, isOnline {
                // Cloud providers are batch (streaming comes in Phase 5 with openAIRealtime).
                return .start(provider: configured, mode: .batch)
            }
            // Fall back to local.
            guard localModelInstalled else { return .blocked(.localModelNotInstalled) }
            let mode: ASRMode = localEngineCapabilities.supportsStreaming ? .streaming : .batch
            return .start(provider: .local, mode: mode)
        }
    }
}
