import Foundation

public enum VoiceTranscriptStatus: String, Sendable, Equatable {
    case success
    case failed
    case retriedFrom
}

public enum VoiceTranscriptFailedStage: String, Sendable, Equatable {
    case asr
    case cleanup
    case paste
    case cancelled
    case unknown
}

public struct VoiceTranscriptDraft: Sendable {
    public let startedAt: Date
    public let endedAt: Date
    public let rawText: String
    public let cleanedText: String
    public let appBundleID: String?
    public let language: VoiceLanguage
    public let modelIdentifier: String
    public let audioPath: String?
    public let status: VoiceTranscriptStatus
    public let failedStage: VoiceTranscriptFailedStage?
    public let failureReason: String?
    public let retrySourceTranscriptID: String?

    public init(
        startedAt: Date,
        endedAt: Date,
        rawText: String,
        cleanedText: String,
        appBundleID: String?,
        language: VoiceLanguage,
        modelIdentifier: String,
        audioPath: String?,
        status: VoiceTranscriptStatus = .success,
        failedStage: VoiceTranscriptFailedStage? = nil,
        failureReason: String? = nil,
        retrySourceTranscriptID: String? = nil
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.appBundleID = appBundleID
        self.language = language
        self.modelIdentifier = modelIdentifier
        self.audioPath = audioPath
        self.status = status
        self.failedStage = failedStage
        self.failureReason = failureReason
        self.retrySourceTranscriptID = retrySourceTranscriptID
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
    public let status: VoiceTranscriptStatus
    public let failedStage: VoiceTranscriptFailedStage?
    public let failureReason: String?
    public let retrySourceTranscriptID: String?

    public init(
        id: String,
        startedAt: Date,
        endedAt: Date,
        durationMs: Int,
        rawText: String,
        cleanedText: String,
        appBundleID: String?,
        language: VoiceLanguage,
        modelIdentifier: String,
        audioPath: String?,
        status: VoiceTranscriptStatus = .success,
        failedStage: VoiceTranscriptFailedStage? = nil,
        failureReason: String? = nil,
        retrySourceTranscriptID: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMs = durationMs
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.appBundleID = appBundleID
        self.language = language
        self.modelIdentifier = modelIdentifier
        self.audioPath = audioPath
        self.status = status
        self.failedStage = failedStage
        self.failureReason = failureReason
        self.retrySourceTranscriptID = retrySourceTranscriptID
    }
}
