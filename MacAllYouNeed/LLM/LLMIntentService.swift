import Core
import Foundation

struct LLMIntentService {
    private let makeProvider: () -> (any VoiceLLMProvider)?

    init(makeProvider: @escaping () -> (any VoiceLLMProvider)?) {
        self.makeProvider = makeProvider
    }

    func run(template: LLMIntentTemplate, input: String, voiceContext: VoicePromptContext) async -> String? {
        guard let provider = makeProvider() else { return nil }
        let request = VoiceLLMRequest(
            text: input,
            rawText: input,
            appBundleID: voiceContext.appBundleID,
            language: voiceContext.language,
            dictionaryEntries: voiceContext.dictionaryEntries,
            translationTarget: voiceContext.translationTarget,
            appInstructions: voiceContext.appInstructions,
            personalStyleNotes: voiceContext.personalStyleNotes,
            personalizationSummary: voiceContext.personalizationSummary,
            recentExamples: voiceContext.recentExamples
        )
        do {
            let output = try await provider.clean(request)
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }
}

extension LLMIntentService {
    /// Production convenience: build a provider from cleanup settings + keychain.
    init(settings: VoiceCleanupSettings, keyStore: VoiceCleanupKeyStore) {
        self.init(makeProvider: {
            (try? VoiceCleanupProviderFactory.makeProvider(settings: settings, keyStore: keyStore)) ?? nil
        })
    }
}
