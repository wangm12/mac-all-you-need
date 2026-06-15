import Foundation

/// Describes static capabilities of an ASR engine. Read by the decision tree
/// before instantiating a session so no engine object is needed at planning time.
public struct VoiceASRCapabilities: Sendable, Equatable {
    /// Engine can produce a live streaming session (via makeLiveSession).
    public var supportsStreaming: Bool
    /// Engine requires network access (cloud engines). False = local/on-device.
    public var requiresNetwork: Bool
    /// Session emits true partial transcripts during recording (not just a final).
    /// Qwen3 pseudo-streaming = supportsStreaming:true, emitsPartials:false today.
    public var emitsPartials: Bool

    public static let batchOnly = VoiceASRCapabilities(
        supportsStreaming: false, requiresNetwork: false, emitsPartials: false
    )

    public init(supportsStreaming: Bool, requiresNetwork: Bool, emitsPartials: Bool) {
        self.supportsStreaming = supportsStreaming
        self.requiresNetwork = requiresNetwork
        self.emitsPartials = emitsPartials
    }
}

public struct VoiceTranscriptionResult: Sendable, Equatable {
    public let text: String
    public let language: VoiceLanguage
    public let modelIdentifier: String

    public init(text: String, language: VoiceLanguage, modelIdentifier: String) {
        self.text = text
        self.language = language
        self.modelIdentifier = modelIdentifier
    }
}

public struct VoiceTranscriptionOptions: Sendable, Equatable {
    public var preferredModelIdentifier: String?

    public init(preferredModelIdentifier: String? = nil) {
        self.preferredModelIdentifier = preferredModelIdentifier
    }

    public static let `default` = VoiceTranscriptionOptions()
}

public protocol VoiceTranscriptionEngine: Sendable {
    var modelIdentifier: String { get }
    var capabilities: VoiceASRCapabilities { get }
    func transcribe(
        samples: [Float],
        sampleRate: Double,
        options: VoiceTranscriptionOptions
    ) async throws -> VoiceTranscriptionResult
}

public extension VoiceTranscriptionEngine {
    var capabilities: VoiceASRCapabilities { .batchOnly }
    func transcribe(samples: [Float], sampleRate: Double) async throws -> VoiceTranscriptionResult {
        try await transcribe(samples: samples, sampleRate: sampleRate, options: .default)
    }
}

// MARK: - Live transcription (background streaming during recording)

public enum VoiceLiveTranscriptionError: Error, Sendable, Equatable {
    case unsupportedEngine
    case cancelled
}

/// Engines that can transcribe incrementally while the mic is open.
public protocol VoiceLiveTranscriptionEngine: VoiceTranscriptionEngine {
    func makeLiveSession(options: VoiceTranscriptionOptions) async throws -> any VoiceLiveTranscriptionSession
}

/// Full capture passed to `finish(context:)` so live sessions can widen the tail window on stop.
public struct VoiceLiveFinishContext: Sendable, Equatable {
    public let samples: [Float]
    public let sampleRate: Double

    public init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }
}

/// A partial (in-progress) transcript emitted by a streaming session.
public struct VoiceTranscriptionPartial: Sendable, Equatable {
    /// Best current full hypothesis (already overlap-merged by the session).
    public let text: String
    /// True if this portion of the transcript is committed (won't change).
    public let isStable: Bool

    public init(text: String, isStable: Bool) {
        self.text = text
        self.isStable = isStable
    }
}

/// One dictation session. Samples are fed in capture order; `finish` returns the final transcript.
public protocol VoiceLiveTranscriptionSession: Sendable {
    func enqueueAudio(samples: [Float], sampleRate: Double) async throws
    /// Register a callback to receive partial results as they become available.
    /// Default implementation is a no-op (batch sessions don't emit partials).
    func setPartialHandler(_ handler: @escaping @Sendable (VoiceTranscriptionPartial) -> Void) async
    func finish() async throws -> VoiceTranscriptionResult
    func finish(context: VoiceLiveFinishContext?) async throws -> VoiceTranscriptionResult
    func cancel() async
}

public extension VoiceLiveTranscriptionSession {
    func setPartialHandler(_ handler: @escaping @Sendable (VoiceTranscriptionPartial) -> Void) async {
        // No-op default — batch/non-partial sessions ignore this.
    }
    func finish(context _: VoiceLiveFinishContext?) async throws -> VoiceTranscriptionResult {
        try await finish()
    }
}
