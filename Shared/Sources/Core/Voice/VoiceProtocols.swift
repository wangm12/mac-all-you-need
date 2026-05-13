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

public protocol VoiceTranscriptionEngine: Sendable {
    var modelIdentifier: String { get }
    func transcribe(samples: [Float], sampleRate: Double) async throws -> VoiceTranscriptionResult
}
