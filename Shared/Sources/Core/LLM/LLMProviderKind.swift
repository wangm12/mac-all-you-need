import Foundation

/// Identifies an LLM provider for AI features (voice cleanup, file organizer, etc.).
public enum LLMProviderKind: String, CaseIterable, Codable, Equatable, Identifiable {
    case anthropic
    case openAICompatible
    case groq
    case gemini
    case ollama
    case omlx

    public var id: String {
        rawValue
    }

    /// Provider name for pickers, settings summaries, and validation copy (not a specific model ID).
    public var label: String {
        switch self {
        case .anthropic:
            "Anthropic"
        case .openAICompatible:
            "OpenAI"
        case .groq:
            "Groq"
        case .gemini:
            "Google"
        case .ollama:
            "Ollama"
        case .omlx:
            "oMLX"
        }
    }

    public var defaultModel: String {
        switch self {
        case .anthropic:
            "claude-haiku-4-5"
        case .openAICompatible:
            "gpt-5-nano"
        case .groq:
            "openai/gpt-oss-20b"
        case .gemini:
            "gemini-2.5-flash"
        case .ollama:
            "qwen2.5:3b-instruct"
        case .omlx:
            "qwen2.5-3b-instruct"
        }
    }

    public var defaultBaseURLString: String {
        switch self {
        case .anthropic:
            "https://api.anthropic.com"
        case .openAICompatible:
            "https://api.openai.com/v1"
        case .groq:
            "https://api.groq.com/openai/v1"
        case .gemini:
            "https://generativelanguage.googleapis.com/v1beta/openai/"
        case .ollama:
            "http://localhost:11434/v1"
        case .omlx:
            "http://127.0.0.1:8000/v1"
        }
    }

    public var requiresAPIKey: Bool {
        switch self {
        case .anthropic, .openAICompatible, .groq, .gemini:
            true
        case .ollama, .omlx:
            false
        }
    }
}
