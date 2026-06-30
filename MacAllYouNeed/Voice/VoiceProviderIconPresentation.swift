import Foundation

/// Brand marks and SF Symbol fallbacks for voice provider rows.
///
/// Cloud/local marks are bundled under `Assets.xcassets` (`VoiceBrand*`).
/// Sources (fetched 2026-05): Anthropic, Google, Ollama — [Simple Icons](https://simpleicons.org) (CC0);
/// OpenAI blossom — [Lobe Icons](https://github.com/lobehub/lobe-icons) (traced from OpenAI brand);
/// Groq — `https://groq.com/favicon.svg`.
enum VoiceProviderIconPresentation {
    enum BrandAsset {
        static let anthropic = "VoiceBrandAnthropic"
        static let openAI = "VoiceBrandOpenAI"
        static let groq = "VoiceBrandGroq"
        static let google = "VoiceBrandGoogle"
        static let ollama = "VoiceBrandOllama"
    }

    static func pickerIcon(for provider: VoiceCleanupProviderKind) -> VoicePickerRowIcon {
        switch provider {
        case .anthropic:
            .brandAsset(BrandAsset.anthropic)
        case .openAICompatible:
            .brandAsset(BrandAsset.openAI)
        case .groq:
            .brandAsset(BrandAsset.groq)
        case .gemini:
            .brandAsset(BrandAsset.google)
        case .ollama:
            .brandAsset(BrandAsset.ollama)
        case .omlx:
            .systemSymbol("flask.fill")
        }
    }

    static func pickerIcon(for providerKind: VoiceASRProviderKind) -> VoicePickerRowIcon {
        switch providerKind {
        case .local:
            pickerIcon(for: .qwenCoreML)
        case .groq:
            .brandAsset(BrandAsset.groq)
        case .openAITranscribe, .openAIRealtime:
            .brandAsset(BrandAsset.openAI)
        case .elevenLabs, .deepgram:
            pickerIcon(for: voiceModelRuntime(for: providerKind))
        }
    }

    static func pickerIcon(for runtime: VoiceModelRuntime) -> VoicePickerRowIcon {
        switch runtime {
        case .anthropic:
            .brandAsset(BrandAsset.anthropic)
        case .openAICompatible, .openAITranscribe:
            .brandAsset(BrandAsset.openAI)
        case .groq:
            .brandAsset(BrandAsset.groq)
        case .elevenLabs:
            .systemSymbol("waveform.circle")
        case .deepgram:
            .systemSymbol("waveform.badge.mic")
        case .ollama:
            .brandAsset(BrandAsset.ollama)
        case .qwenCoreML, .parakeetCoreML, .sensevoice:
            .systemSymbol("internaldrive.fill")
        case .whisperKit:
            .systemSymbol("flask.fill")
        }
    }

    /// Legacy SF Symbol name; prefer `pickerIcon(for:)`.
    static func pickerSymbol(for provider: VoiceCleanupProviderKind) -> String {
        symbolName(from: pickerIcon(for: provider))
    }

    static func pickerSymbol(for providerKind: VoiceASRProviderKind) -> String {
        symbolName(from: pickerIcon(for: providerKind))
    }

    static func pickerSymbol(for runtime: VoiceModelRuntime) -> String {
        symbolName(from: pickerIcon(for: runtime))
    }

    private static func symbolName(from icon: VoicePickerRowIcon) -> String {
        switch icon {
        case let .brandAsset(name):
            name
        case let .systemSymbol(name):
            name
        }
    }

    private static func voiceModelRuntime(for providerKind: VoiceASRProviderKind) -> VoiceModelRuntime {
        switch providerKind {
        case .local:
            .qwenCoreML
        case .groq:
            .groq
        case .elevenLabs:
            .elevenLabs
        case .openAITranscribe, .openAIRealtime:
            .openAITranscribe
        case .deepgram:
            .deepgram
        }
    }
}
