import Foundation

public struct VoiceTranscriptDraft: Sendable {
    public let startedAt: Date
    public let endedAt: Date
    public let rawText: String
    public let cleanedText: String
    public let appBundleID: String?
    public let language: VoiceLanguage
    public let modelIdentifier: String
    public let audioPath: String?

    public init(
        startedAt: Date,
        endedAt: Date,
        rawText: String,
        cleanedText: String,
        appBundleID: String?,
        language: VoiceLanguage,
        modelIdentifier: String,
        audioPath: String?
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.appBundleID = appBundleID
        self.language = language
        self.modelIdentifier = modelIdentifier
        self.audioPath = audioPath
    }
}

public struct VoiceTranscript: Identifiable, Sendable, Equatable {
    public let id: String
    public let startedAt: Date
    public let endedAt: Date
    public let durationMs: Int
    public let rawText: String
    public let cleanedText: String
    public let appBundleID: String?
    public let language: VoiceLanguage
    public let modelIdentifier: String
    public let audioPath: String?
}
