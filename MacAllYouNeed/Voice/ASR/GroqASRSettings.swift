import Core
import Foundation

// MARK: - Provider kind

enum VoiceASRProviderKind: String, CaseIterable, Codable, Equatable, Identifiable {
    case local
    case groq
    case elevenLabs
    case openAITranscribe
    case deepgram

    var id: String { rawValue }

    var label: String {
        switch self {
        case .local: "Local"
        case .groq: "Groq Whisper"
        case .elevenLabs: "ElevenLabs Scribe"
        case .openAITranscribe: "OpenAI Transcribe"
        case .deepgram: "Deepgram Nova"
        }
    }

    var subtitle: String {
        switch self {
        case .local: "On-device, private. Qwen3 for Chinese/English or Parakeet for English/European languages."
        case .groq: "Cloud via Groq. Best code-switching quality. Requires API key."
        case .elevenLabs: "Cloud via ElevenLabs Scribe v2. Good for high-quality multilingual transcription. Requires API key."
        case .openAITranscribe: "Cloud via OpenAI's transcription API. Strong general-purpose accuracy. Requires API key."
        case .deepgram: "Cloud via Deepgram Nova-3. Fast pre-recorded transcription. Requires API key."
        }
    }

    var apiKeyLabel: String {
        switch self {
        case .local:
            "API key"
        case .groq:
            "Groq API key"
        case .elevenLabs:
            "ElevenLabs API key"
        case .openAITranscribe:
            "OpenAI API key"
        case .deepgram:
            "Deepgram API key"
        }
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .local:
            ""
        case .groq:
            "gsk_..."
        case .elevenLabs:
            "xi_..."
        case .openAITranscribe:
            "sk-..."
        case .deepgram:
            "Deepgram API key"
        }
    }

    var isCloud: Bool {
        switch self {
        case .local:
            false
        case .groq, .elevenLabs, .openAITranscribe, .deepgram:
            true
        }
    }
}

// MARK: - Groq model

enum GroqASRModelID: String, CaseIterable, Codable, Equatable, Identifiable {
    case whisperLargeV3Turbo = "whisper-large-v3-turbo"
    case whisperLargeV3 = "whisper-large-v3"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .whisperLargeV3Turbo: "Whisper Large V3 Turbo"
        case .whisperLargeV3: "Whisper Large V3"
        }
    }

    var subtitle: String {
        switch self {
        case .whisperLargeV3Turbo: "Faster · $0.04/hr · Recommended"
        case .whisperLargeV3: "More accurate · $0.111/hr"
        }
    }
}

// MARK: - Groq settings

struct GroqASRSettings: Codable, Equatable {
    var modelID: GroqASRModelID
    var languageHint: VoiceASRLanguageHint

    static let `default` = GroqASRSettings(
        modelID: .whisperLargeV3Turbo,
        languageHint: .automatic
    )

    /// ISO-639-1 code to send to Groq, or nil for automatic detection.
    var groqLanguageCode: String? {
        switch languageHint {
        case .automatic: nil
        case .chinese: "zh"
        case .english: "en"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case modelID
        case languageHint
    }

    init(modelID: GroqASRModelID = .whisperLargeV3Turbo,
         languageHint: VoiceASRLanguageHint = .automatic) {
        self.modelID = modelID
        self.languageHint = languageHint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelID = try container.decodeIfPresent(GroqASRModelID.self, forKey: .modelID)
            ?? GroqASRSettings.default.modelID
        languageHint = try container.decodeIfPresent(VoiceASRLanguageHint.self, forKey: .languageHint)
            ?? GroqASRSettings.default.languageHint
    }
}

enum GroqASRSettingsStore {
    static let key = "voice.asr.groq.settings.v1"

    static func load(from defaults: UserDefaults = AppGroupSettings.defaults) -> GroqASRSettings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(GroqASRSettings.self, from: data)
        else { return .default }
        return decoded
    }

    static func save(_ settings: GroqASRSettings, to defaults: UserDefaults = AppGroupSettings.defaults) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

// MARK: - Shared cloud ASR settings

enum VoiceCloudASRModelID: String, CaseIterable, Codable, Equatable, Identifiable {
    case groqWhisperLargeV3Turbo = "groq.whisper-large-v3-turbo"
    case groqWhisperLargeV3 = "groq.whisper-large-v3"
    case elevenLabsScribeV2 = "elevenLabs.scribe_v2"
    case openAIGPT4oTranscribe = "openAITranscribe.gpt-4o-transcribe"
    case deepgramNova3 = "deepgram.nova-3"

    var id: String { rawValue }

    var providerKind: VoiceASRProviderKind {
        switch self {
        case .groqWhisperLargeV3Turbo, .groqWhisperLargeV3:
            .groq
        case .elevenLabsScribeV2:
            .elevenLabs
        case .openAIGPT4oTranscribe:
            .openAITranscribe
        case .deepgramNova3:
            .deepgram
        }
    }

    var providerModelID: String {
        switch self {
        case .groqWhisperLargeV3Turbo:
            "whisper-large-v3-turbo"
        case .groqWhisperLargeV3:
            "whisper-large-v3"
        case .elevenLabsScribeV2:
            "scribe_v2"
        case .openAIGPT4oTranscribe:
            "gpt-4o-transcribe"
        case .deepgramNova3:
            "nova-3"
        }
    }

    var title: String {
        switch self {
        case .groqWhisperLargeV3Turbo:
            "Groq Whisper Large V3 Turbo"
        case .groqWhisperLargeV3:
            "Groq Whisper Large V3"
        case .elevenLabsScribeV2:
            "ElevenLabs Scribe v2"
        case .openAIGPT4oTranscribe:
            "OpenAI GPT-4o Transcribe"
        case .deepgramNova3:
            "Deepgram Nova-3"
        }
    }

    var subtitle: String {
        switch self {
        case .groqWhisperLargeV3Turbo:
            "Fast Whisper-compatible cloud ASR. Recommended Groq default."
        case .groqWhisperLargeV3:
            "More accurate Groq Whisper option for longer or harder dictation."
        case .elevenLabsScribeV2:
            "High-quality Scribe v2 batch transcription via ElevenLabs BYOK."
        case .openAIGPT4oTranscribe:
            "OpenAI speech-to-text with JSON response and optional language hint."
        case .deepgramNova3:
            "Deepgram Nova-3 pre-recorded transcription with smart formatting."
        }
    }

    static func defaultModel(for providerKind: VoiceASRProviderKind) -> VoiceCloudASRModelID {
        switch providerKind {
        case .local:
            .groqWhisperLargeV3Turbo
        case .groq:
            .groqWhisperLargeV3Turbo
        case .elevenLabs:
            .elevenLabsScribeV2
        case .openAITranscribe:
            .openAIGPT4oTranscribe
        case .deepgram:
            .deepgramNova3
        }
    }

    init?(groqModelID: GroqASRModelID) {
        switch groqModelID {
        case .whisperLargeV3Turbo:
            self = .groqWhisperLargeV3Turbo
        case .whisperLargeV3:
            self = .groqWhisperLargeV3
        }
    }

    var groqModelID: GroqASRModelID? {
        switch self {
        case .groqWhisperLargeV3Turbo:
            .whisperLargeV3Turbo
        case .groqWhisperLargeV3:
            .whisperLargeV3
        default:
            nil
        }
    }
}

struct VoiceCloudASRSettings: Codable, Equatable {
    var modelID: VoiceCloudASRModelID
    var languageHint: VoiceASRLanguageHint

    static let `default` = VoiceCloudASRSettings(
        modelID: .groqWhisperLargeV3Turbo,
        languageHint: .automatic
    )

    init(
        modelID: VoiceCloudASRModelID = .groqWhisperLargeV3Turbo,
        languageHint: VoiceASRLanguageHint = .automatic
    ) {
        self.modelID = modelID
        self.languageHint = languageHint
    }

    func modelID(for providerKind: VoiceASRProviderKind) -> VoiceCloudASRModelID {
        modelID.providerKind == providerKind ? modelID : VoiceCloudASRModelID.defaultModel(for: providerKind)
    }

    var iso639LanguageCode: String? {
        switch languageHint {
        case .automatic:
            nil
        case .chinese:
            "zh"
        case .english:
            "en"
        }
    }

    func updating(modelID: VoiceCloudASRModelID) -> VoiceCloudASRSettings {
        VoiceCloudASRSettings(modelID: modelID, languageHint: languageHint)
    }
}

enum VoiceCloudASRSettingsStore {
    static let key = "voice.asr.cloud.settings.v1"

    static func load(from defaults: UserDefaults = AppGroupSettings.defaults) -> VoiceCloudASRSettings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(VoiceCloudASRSettings.self, from: data)
        else {
            let legacy = GroqASRSettingsStore.load(from: defaults)
            return VoiceCloudASRSettings(
                modelID: VoiceCloudASRModelID(groqModelID: legacy.modelID) ?? VoiceCloudASRSettings.default.modelID,
                languageHint: legacy.languageHint
            )
        }
        return decoded
    }

    static func save(_ settings: VoiceCloudASRSettings, to defaults: UserDefaults = AppGroupSettings.defaults) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
        if let groqModelID = settings.modelID.groqModelID {
            GroqASRSettingsStore.save(
                GroqASRSettings(modelID: groqModelID, languageHint: settings.languageHint),
                to: defaults
            )
        }
    }
}
