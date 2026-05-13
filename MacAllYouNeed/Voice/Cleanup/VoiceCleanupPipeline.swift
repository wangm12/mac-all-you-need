import Core
import Foundation

struct VoiceCleanupRequest: Equatable {
    let rawText: String
    let appBundleID: String?
    let language: VoiceLanguage
    let dictionaryEntries: [VoiceDictionaryEntry]
    let appInstructions: String?

    init(
        rawText: String,
        appBundleID: String?,
        language: VoiceLanguage,
        dictionaryEntries: [VoiceDictionaryEntry] = [],
        appInstructions: String? = nil
    ) {
        self.rawText = rawText
        self.appBundleID = appBundleID
        self.language = language
        self.dictionaryEntries = dictionaryEntries
        self.appInstructions = appInstructions
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

    init(
        text: String,
        rawText: String,
        appBundleID: String?,
        language: VoiceLanguage,
        dictionaryEntries: [VoiceDictionaryEntry] = [],
        translationTarget: VoiceLanguage? = nil,
        appInstructions: String? = nil
    ) {
        self.text = text
        self.rawText = rawText
        self.appBundleID = appBundleID
        self.language = language
        self.dictionaryEntries = dictionaryEntries
        self.translationTarget = translationTarget
        self.appInstructions = appInstructions
    }

    var promptContext: VoicePromptContext {
        VoicePromptContext(
            language: language,
            appBundleID: appBundleID,
            dictionaryEntries: dictionaryEntries,
            translationTarget: translationTarget,
            appInstructions: appInstructions
        )
    }
}

struct VoiceCleanupResult: Equatable {
    let rawText: String
    let cleanedText: String
    let usedLLM: Bool
    let providerIdentifier: String?
}

protocol VoiceLLMProvider: Sendable {
    var providerIdentifier: String { get }
    func clean(_ request: VoiceLLMRequest) async throws -> String
}

struct VoiceCleanupPipeline {
    private let provider: (any VoiceLLMProvider)?
    private let timeout: Duration

    init(provider: (any VoiceLLMProvider)? = nil, timeout: Duration = .seconds(7)) {
        self.provider = provider
        self.timeout = timeout
    }

    func clean(_ request: VoiceCleanupRequest) async -> VoiceCleanupResult {
        let localText = VoiceLocalTextCleaner.clean(request.rawText)
        guard let provider, Self.speechUnitCount(in: localText) >= 3 else {
            return VoiceCleanupResult(
                rawText: request.rawText,
                cleanedText: applyDictionary(to: localText, entries: request.dictionaryEntries),
                usedLLM: false,
                providerIdentifier: nil
            )
        }

        let llmRequest = VoiceLLMRequest(
            text: localText,
            rawText: request.rawText,
            appBundleID: request.appBundleID,
            language: request.language,
            dictionaryEntries: request.dictionaryEntries,
            appInstructions: request.appInstructions
        )

        do {
            let llmText = try await cleanWithTimeout(provider: provider, request: llmRequest)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !llmText.isEmpty else {
                return fallback(request: request, localText: localText, providerIdentifier: provider.providerIdentifier)
            }
            return VoiceCleanupResult(
                rawText: request.rawText,
                cleanedText: applyDictionary(to: llmText, entries: request.dictionaryEntries),
                usedLLM: true,
                providerIdentifier: provider.providerIdentifier
            )
        } catch {
            return fallback(request: request, localText: localText, providerIdentifier: provider.providerIdentifier)
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
        providerIdentifier: String?
    ) -> VoiceCleanupResult {
        VoiceCleanupResult(
            rawText: request.rawText,
            cleanedText: applyDictionary(to: localText, entries: request.dictionaryEntries),
            usedLLM: false,
            providerIdentifier: providerIdentifier
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
}

private enum VoiceCleanupPipelineError: Error {
    case timedOut
}
