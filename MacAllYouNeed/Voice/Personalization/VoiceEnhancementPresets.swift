import Foundation

struct VoiceEnhancementPresetItem: Identifiable {
    let id: String
    let title: String
    let prompt: String
}

enum VoiceEnhancementPresets {
    static let email = """
        Use a concise professional email tone. Prefer complete sentences and standard greetings/sign-offs when appropriate.
        """

    static let slack = """
        Use a casual Slack tone. Short sentences are fine. Prefer plain language over formal phrasing.
        """

    static let code = """
        Preserve technical terms, identifiers, and code symbols verbatim. Do not “correct” API names or camelCase.
        """

    static let all: [VoiceEnhancementPresetItem] = [
        VoiceEnhancementPresetItem(id: "email", title: "Email", prompt: email),
        VoiceEnhancementPresetItem(id: "slack", title: "Slack", prompt: slack),
        VoiceEnhancementPresetItem(id: "code", title: "Code", prompt: code)
    ]
}
