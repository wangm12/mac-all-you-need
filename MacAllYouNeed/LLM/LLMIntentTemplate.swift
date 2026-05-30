import Core
import Foundation

enum LLMIntentTemplate {
    case voiceCleanup

    func systemPrompt(voiceContext: VoicePromptContext) -> String {
        switch self {
        case .voiceCleanup: return VoicePromptBuilder.systemPrompt(context: voiceContext)
        }
    }

    func userPrompt(input: String) -> String {
        switch self {
        case .voiceCleanup: return VoicePromptBuilder.userPrompt(transcript: input)
        }
    }
}
