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
