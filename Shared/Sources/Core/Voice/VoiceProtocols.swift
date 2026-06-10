import Foundation

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
    func transcribe(
        samples: [Float],
        sampleRate: Double,
        options: VoiceTranscriptionOptions
    ) async throws -> VoiceTranscriptionResult
}

public extension VoiceTranscriptionEngine {
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

/// One dictation session. Samples are fed in capture order; `finish` returns the final transcript.
public protocol VoiceLiveTranscriptionSession: Sendable {
    func enqueueAudio(samples: [Float], sampleRate: Double) async throws
    func finish() async throws -> VoiceTranscriptionResult
    func finish(context: VoiceLiveFinishContext?) async throws -> VoiceTranscriptionResult
    func cancel() async
}

public extension VoiceLiveTranscriptionSession {
    func finish(context _: VoiceLiveFinishContext?) async throws -> VoiceTranscriptionResult {
        try await finish()
    }
}
