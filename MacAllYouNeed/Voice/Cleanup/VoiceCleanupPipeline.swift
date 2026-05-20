import Core
import Foundation
import OSLog

private let log = Logger(subsystem: "com.macallyouneed.voice", category: "cleanup")

struct VoiceCleanupRequest: Equatable {
    let rawText: String
    let appBundleID: String?
    let language: VoiceLanguage
    let dictionaryEntries: [VoiceDictionaryEntry]
    let appInstructions: String?
    let personalStyleNotes: String?
    let personalizationSummary: String?
    let recentExamples: [(before: String, after: String)]

    init(
        rawText: String,
        appBundleID: String?,
        language: VoiceLanguage,
        dictionaryEntries: [VoiceDictionaryEntry] = [],
        appInstructions: String? = nil,
        personalStyleNotes: String? = nil,
        personalizationSummary: String? = nil,
        recentExamples: [(before: String, after: String)] = []
    ) {
        self.rawText = rawText
        self.appBundleID = appBundleID
        self.language = language
        self.dictionaryEntries = dictionaryEntries
        self.appInstructions = appInstructions
        self.personalStyleNotes = personalStyleNotes
        self.personalizationSummary = personalizationSummary
        self.recentExamples = recentExamples
    }

    // Equatable: manually handle tuple array.
    static func == (lhs: VoiceCleanupRequest, rhs: VoiceCleanupRequest) -> Bool {
        lhs.rawText == rhs.rawText
            && lhs.appBundleID == rhs.appBundleID
            && lhs.language == rhs.language
            && lhs.dictionaryEntries == rhs.dictionaryEntries
            && lhs.appInstructions == rhs.appInstructions
            && lhs.personalStyleNotes == rhs.personalStyleNotes
            && lhs.personalizationSummary == rhs.personalizationSummary
            && lhs.recentExamples.count == rhs.recentExamples.count
    }
}

struct VoiceLLMRequest: Equatable {
    let text: String
    let rawText: String
    let appBundleID: String?
    let language: VoiceLanguage
    let dictionaryEntries: [VoiceDictionaryEntry]
    let translationTarget: VoiceLanguage?
    let appInstructions: String?
    let personalStyleNotes: String?
    let personalizationSummary: String?
    let recentExamples: [(before: String, after: String)]

    init(
        text: String,
        rawText: String,
        appBundleID: String?,
        language: VoiceLanguage,
        dictionaryEntries: [VoiceDictionaryEntry] = [],
        translationTarget: VoiceLanguage? = nil,
        appInstructions: String? = nil,
        personalStyleNotes: String? = nil,
        personalizationSummary: String? = nil,
        recentExamples: [(before: String, after: String)] = []
    ) {
        self.text = text
        self.rawText = rawText
        self.appBundleID = appBundleID
        self.language = language
        self.dictionaryEntries = dictionaryEntries
        self.translationTarget = translationTarget
        self.appInstructions = appInstructions
        self.personalStyleNotes = personalStyleNotes
        self.personalizationSummary = personalizationSummary
        self.recentExamples = recentExamples
    }

    var promptContext: VoicePromptContext {
        VoicePromptContext(
            language: language,
            appBundleID: appBundleID,
            dictionaryEntries: dictionaryEntries,
            translationTarget: translationTarget,
            appInstructions: appInstructions,
            personalStyleNotes: personalStyleNotes,
            personalizationSummary: personalizationSummary,
            recentExamples: recentExamples
        )
    }

    // Equatable: manually handle tuple array.
    static func == (lhs: VoiceLLMRequest, rhs: VoiceLLMRequest) -> Bool {
        lhs.text == rhs.text
            && lhs.rawText == rhs.rawText
            && lhs.appBundleID == rhs.appBundleID
            && lhs.language == rhs.language
            && lhs.dictionaryEntries == rhs.dictionaryEntries
            && lhs.translationTarget == rhs.translationTarget
            && lhs.appInstructions == rhs.appInstructions
            && lhs.personalStyleNotes == rhs.personalStyleNotes
            && lhs.personalizationSummary == rhs.personalizationSummary
            && lhs.recentExamples.count == rhs.recentExamples.count
    }
}

struct VoiceCleanupResult: Equatable {
    let rawText: String
    let cleanedText: String
    let usedLLM: Bool
    let providerIdentifier: String?
    let fallbackReason: VoiceCleanupFallbackReason?
    let asrMs: Int?
    let cleanupMs: Int
    let totalMs: Int?
    let deadlineExceeded: Bool

    init(
        rawText: String,
        cleanedText: String,
        usedLLM: Bool,
        providerIdentifier: String?,
        fallbackReason: VoiceCleanupFallbackReason? = nil,
        asrMs: Int? = nil,
        cleanupMs: Int = 0,
        totalMs: Int? = nil,
        deadlineExceeded: Bool = false
    ) {
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.usedLLM = usedLLM
        self.providerIdentifier = providerIdentifier
        self.fallbackReason = fallbackReason
        self.asrMs = asrMs
        self.cleanupMs = cleanupMs
        self.totalMs = totalMs
        self.deadlineExceeded = deadlineExceeded
    }

    func withTimings(asrMs: Int?, cleanupMs: Int, totalMs: Int) -> VoiceCleanupResult {
        VoiceCleanupResult(
            rawText: rawText,
            cleanedText: cleanedText,
            usedLLM: usedLLM,
            providerIdentifier: providerIdentifier,
            fallbackReason: fallbackReason,
            asrMs: asrMs,
            cleanupMs: cleanupMs,
            totalMs: totalMs,
            deadlineExceeded: deadlineExceeded
        )
    }
}

enum VoiceCleanupFallbackReason: String, Codable, Equatable {
    case providerUnavailable
    case transcriptTooShort
    case emptyResponse
    case deadlineExceeded
    case providerError
    case forcedLocal
}

protocol VoiceLLMProvider: Sendable {
    var providerIdentifier: String { get }
    func clean(_ request: VoiceLLMRequest) async throws -> String
}

/// Narrow protocol for text generation with explicit system + user prompts.
/// Used by VoicePersonalizationSummarizer to generate style summaries without
/// fighting the cleanup-specific prompt that VoiceLLMProvider.clean() injects.
protocol VoiceTextGenerationProvider: Sendable {
    var providerIdentifier: String { get }
    func generate(systemPrompt: String, userText: String) async throws -> String
}

struct VoiceCleanupPipeline {
    private let provider: (any VoiceLLMProvider)?
    private let timeout: Duration
    private let forcedFallbackReason: VoiceCleanupFallbackReason?
    private let forcedDeadlineExceeded: Bool

    init(
        provider: (any VoiceLLMProvider)? = nil,
        timeout: Duration = .seconds(7),
        forcedFallbackReason: VoiceCleanupFallbackReason? = nil,
        forcedDeadlineExceeded: Bool = false
    ) {
        self.provider = provider
        self.timeout = timeout
        self.forcedFallbackReason = forcedFallbackReason
        self.forcedDeadlineExceeded = forcedDeadlineExceeded
    }

    func clean(_ request: VoiceCleanupRequest) async -> VoiceCleanupResult {
        let startedAt = Date()
        let localText = VoiceLocalTextCleaner.clean(request.rawText)
        let speechUnits = Self.speechUnitCount(in: localText)
        guard let provider else {
            log.info("cleanup: local only — provider unavailable")
            return VoiceCleanupResult(
                rawText: request.rawText,
                cleanedText: applyDictionary(to: localText, entries: request.dictionaryEntries),
                usedLLM: false,
                providerIdentifier: nil,
                fallbackReason: forcedFallbackReason ?? .providerUnavailable,
                cleanupMs: Self.elapsedMs(since: startedAt),
                deadlineExceeded: forcedDeadlineExceeded
            )
        }
        guard speechUnits >= 3 else {
            log.info("cleanup: local only — speechUnits \(speechUnits, privacy: .public) < 3")
            return VoiceCleanupResult(
                rawText: request.rawText,
                cleanedText: applyDictionary(to: localText, entries: request.dictionaryEntries),
                usedLLM: false,
                providerIdentifier: provider.providerIdentifier,
                fallbackReason: .transcriptTooShort,
                cleanupMs: Self.elapsedMs(since: startedAt)
            )
        }

        let llmRequest = VoiceLLMRequest(
            text: localText,
            rawText: request.rawText,
            appBundleID: request.appBundleID,
            language: request.language,
            dictionaryEntries: request.dictionaryEntries,
            appInstructions: request.appInstructions,
            personalStyleNotes: request.personalStyleNotes,
            personalizationSummary: request.personalizationSummary,
            recentExamples: request.recentExamples
        )

        do {
            log.info("cleanup: LLM call — provider: \(provider.providerIdentifier, privacy: .public) timeout: \(timeout, privacy: .public)")
            let llmText = try await cleanWithTimeout(provider: provider, request: llmRequest)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !llmText.isEmpty else {
                log.warning("cleanup: LLM returned empty, falling back to local")
                return fallback(
                    request: request,
                    localText: localText,
                    providerIdentifier: provider.providerIdentifier,
                    reason: .emptyResponse,
                    startedAt: startedAt
                )
            }
            log.info("cleanup: LLM ok — outputLength: \(llmText.count, privacy: .public) chars")
            return VoiceCleanupResult(
                rawText: request.rawText,
                cleanedText: applyDictionary(to: llmText, entries: request.dictionaryEntries),
                usedLLM: true,
                providerIdentifier: provider.providerIdentifier,
                cleanupMs: Self.elapsedMs(since: startedAt)
            )
        } catch VoiceCleanupPipelineError.timedOut {
            log.error("cleanup: LLM timed out, falling back to local")
            return fallback(
                request: request,
                localText: localText,
                providerIdentifier: provider.providerIdentifier,
                reason: .deadlineExceeded,
                startedAt: startedAt,
                deadlineExceeded: true
            )
        } catch {
            log.error("cleanup: LLM failed (\(error.localizedDescription, privacy: .public)), falling back to local")
            return fallback(
                request: request,
                localText: localText,
                providerIdentifier: provider.providerIdentifier,
                reason: .providerError,
                startedAt: startedAt
            )
        }
    }

    private func cleanWithTimeout(
        provider: any VoiceLLMProvider,
        request: VoiceLLMRequest
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await provider.clean(request)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw VoiceCleanupPipelineError.timedOut
            }

            let output = try await group.next() ?? ""
            group.cancelAll()
            return output
        }
    }

    private func fallback(
        request: VoiceCleanupRequest,
        localText: String,
        providerIdentifier: String?,
        reason: VoiceCleanupFallbackReason,
        startedAt: Date,
        deadlineExceeded: Bool = false
    ) -> VoiceCleanupResult {
        VoiceCleanupResult(
            rawText: request.rawText,
            cleanedText: applyDictionary(to: localText, entries: request.dictionaryEntries),
            usedLLM: false,
            providerIdentifier: providerIdentifier,
            fallbackReason: reason,
            cleanupMs: Self.elapsedMs(since: startedAt),
            deadlineExceeded: deadlineExceeded
        )
    }

    private func applyDictionary(to text: String, entries: [VoiceDictionaryEntry]) -> String {
        VoiceWordReplacement.apply(text, entries: entries)
    }

    private static func speechUnitCount(in text: String) -> Int {
        var count = 0
        var isInsideLatinOrNumberRun = false

        for scalar in text.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar), !isCJK(scalar) {
                if !isInsideLatinOrNumberRun {
                    count += 1
                    isInsideLatinOrNumberRun = true
                }
                continue
            }

            isInsideLatinOrNumberRun = false
            if isCJK(scalar) {
                count += 1
            }
        }

        return count
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400 ... 0x4DBF,
             0x4E00 ... 0x9FFF,
             0xF900 ... 0xFAFF,
             0x20000 ... 0x2A6DF,
             0x2A700 ... 0x2B73F,
             0x2B740 ... 0x2B81F,
             0x2B820 ... 0x2CEAF:
            true
        default:
            false
        }
    }

    private static func elapsedMs(since date: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(date) * 1000))
    }
}

private enum VoiceCleanupPipelineError: Error {
    case timedOut
}
