import Foundation

/// Groq **chat / completions** model IDs suitable for OpenAI-compatible cleanup calls.
/// Curated from Groq’s published model table (IDs and availability change over time; see Groq docs).
/// https://console.groq.com/docs/rate-limits
enum VoiceGroqCleanupChatModel: String, CaseIterable, Identifiable {
    case llama31_8bInstant = "llama-3.1-8b-instant"
    case llama33_70bVersatile = "llama-3.3-70b-versatile"
    case llama4Scout = "meta-llama/llama-4-scout-17b-16e-instruct"
    case qwen3_32b = "qwen/qwen3-32b"
    case compound = "groq/compound"
    case compoundMini = "groq/compound-mini"
    case gptOss20b = "openai/gpt-oss-20b"
    case gptOss120b = "openai/gpt-oss-120b"

    var id: String { rawValue }

    var pickerTitle: String {
        switch self {
        case .llama31_8bInstant:
            "Llama 3.1 8B Instant"
        case .llama33_70bVersatile:
            "Llama 3.3 70B Versatile"
        case .llama4Scout:
            "Llama 4 Scout 17B"
        case .qwen3_32b:
            "Qwen3 32B"
        case .compound:
            "Groq Compound"
        case .compoundMini:
            "Groq Compound Mini"
        case .gptOss20b:
            "GPT-OSS 20B"
        case .gptOss120b:
            "GPT-OSS 120B"
        }
    }

    /// Stable order for the cleanup picker (fast defaults first).
    static var orderedForPicker: [VoiceGroqCleanupChatModel] {
        [
            .llama31_8bInstant,
            .llama33_70bVersatile,
            .llama4Scout,
            .qwen3_32b,
            .compoundMini,
            .compound,
            .gptOss20b,
            .gptOss120b
        ]
    }

    static func pickerTitle(forModelID id: String) -> String {
        if let known = VoiceGroqCleanupChatModel(rawValue: id) {
            return known.pickerTitle
        }
        return id
    }

    /// Options for `MAYNDropdown`: known models plus the current draft if it is a custom / legacy ID.
    static func dropdownModelIDs(currentDraft: String) -> [String] {
        let trimmed = currentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        var ids = orderedForPicker.map(\.rawValue)
        if !trimmed.isEmpty, !ids.contains(trimmed) {
            ids.append(trimmed)
        }
        return ids
    }
}
