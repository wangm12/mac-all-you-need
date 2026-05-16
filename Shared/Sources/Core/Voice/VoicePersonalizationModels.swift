import Foundation

public enum VoiceAutoSubmitKey: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case returnKey = "return_key"
    case commandReturn = "command_return"

    public var id: String {
        rawValue
    }
}

public struct VoicePersonalizationContext: Identifiable, Equatable, Sendable {
    public static let globalBundleID = "global"
    public static let globalDisplayName = "Global"

    public let id: String
    public let bundleID: String
    public let displayName: String
    public let enabled: Bool
    public let asrModelID: String?
    public let autoSubmitKey: VoiceAutoSubmitKey?
    public let customPromptOverride: String?
    public let styleNotes: String?
    public let summary: String?
    public let summarySourceCount: Int
    public let summaryGeneratedAt: Date?
    public let sampleCount: Int
    public let lastLearnedAt: Date?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: String,
        bundleID: String,
        displayName: String,
        enabled: Bool,
        asrModelID: String?,
        autoSubmitKey: VoiceAutoSubmitKey?,
        customPromptOverride: String?,
        styleNotes: String?,
        summary: String?,
        summarySourceCount: Int,
        summaryGeneratedAt: Date?,
        sampleCount: Int,
        lastLearnedAt: Date?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.bundleID = bundleID
        self.displayName = displayName
        self.enabled = enabled
        self.asrModelID = asrModelID
        self.autoSubmitKey = autoSubmitKey
        self.customPromptOverride = customPromptOverride
        self.styleNotes = styleNotes
        self.summary = summary
        self.summarySourceCount = summarySourceCount
        self.summaryGeneratedAt = summaryGeneratedAt
        self.sampleCount = sampleCount
        self.lastLearnedAt = lastLearnedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isGlobal: Bool {
        bundleID == Self.globalBundleID
    }
}

public struct VoicePersonalizationContextDraft: Equatable, Sendable {
    public var bundleID: String
    public var displayName: String
    public var enabled: Bool
    public var asrModelID: String?
    public var autoSubmitKey: VoiceAutoSubmitKey?
    public var customPromptOverride: String?
    public var styleNotes: String?

    public init(
        bundleID: String,
        displayName: String,
        enabled: Bool = true,
        asrModelID: String? = nil,
        autoSubmitKey: VoiceAutoSubmitKey? = nil,
        customPromptOverride: String? = nil,
        styleNotes: String? = nil
    ) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.enabled = enabled
        self.asrModelID = asrModelID
        self.autoSubmitKey = autoSubmitKey
        self.customPromptOverride = customPromptOverride
        self.styleNotes = styleNotes
    }
}

public struct VoicePersonalizationSample: Identifiable, Equatable, Sendable {
    public let id: String
    public let contextID: String
    public let transcriptID: String?
    public let before: String
    public let after: String
    public let diffOffset: Int
    public let diffLength: Int
    public let observedAt: Date
    public let expiresAt: Date
    public let summarized: Bool

    public init(
        id: String,
        contextID: String,
        transcriptID: String?,
        before: String,
        after: String,
        diffOffset: Int,
        diffLength: Int,
        observedAt: Date,
        expiresAt: Date,
        summarized: Bool
    ) {
        self.id = id
        self.contextID = contextID
        self.transcriptID = transcriptID
        self.before = before
        self.after = after
        self.diffOffset = diffOffset
        self.diffLength = diffLength
        self.observedAt = observedAt
        self.expiresAt = expiresAt
        self.summarized = summarized
    }
}

public enum VoiceTrainingExampleQuality: String, Codable, Equatable, Sendable {
    case high
    case medium
}

public struct VoicePersonalizationSampleDraft: Equatable, Sendable {
    public var contextID: String
    public var transcriptID: String?
    public var before: String
    public var after: String
    public var finalText: String?
    public var quality: VoiceTrainingExampleQuality
    public var qualityReason: String?
    public var diffOffset: Int
    public var diffLength: Int
    public var ttlSeconds: TimeInterval

    public init(
        contextID: String,
        transcriptID: String?,
        before: String,
        after: String,
        finalText: String? = nil,
        quality: VoiceTrainingExampleQuality = .medium,
        qualityReason: String? = nil,
        diffOffset: Int,
        diffLength: Int,
        ttlSeconds: TimeInterval = 30 * 24 * 60 * 60
    ) {
        self.contextID = contextID
        self.transcriptID = transcriptID
        self.before = before
        self.after = after
        self.finalText = finalText
        self.quality = quality
        self.qualityReason = qualityReason
        self.diffOffset = diffOffset
        self.diffLength = diffLength
        self.ttlSeconds = ttlSeconds
    }
}

struct EncryptedSamplePayload: Codable, Equatable {
    let v: Int
    let before: String
    let after: String
    let diffOffset: Int
    let diffLength: Int

    static let currentVersion = 1
}

public enum VoicePersonalizationStoreError: Error, Equatable {
    case emptyBundleID
    case contextNotFound
    case payloadDecodeFailed
    case unsupportedSchemaVersion(Int)
}
