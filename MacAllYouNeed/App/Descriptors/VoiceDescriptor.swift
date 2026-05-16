import FeatureCore
import SwiftUI

enum VoiceDescriptor {
    static func descriptor() -> FeatureDescriptor {
        FeatureDescriptor(
            id: .voice,
            displayName: "Voice Dictation",
            icon: "mic",
            summary: "Push-to-talk voice dictation (cloud or local ASR).",
            detailDescription: "Hold a hotkey, speak, release — text is pasted at the cursor. Supports Groq Whisper (cloud) and Qwen3 (local).",
            requiredPermissions: [.microphone, .accessibility],
            hotkeys: [HotkeyDescriptor(identifier: "voice.pushToTalk", displayName: "Voice push-to-talk")],
            activator: VoiceFeatureActivator(),
            // Phase 05 will replace with VoiceSettingsView(controller: AppController.shared)
            settingsTabFactory: { AnyView(Text("Voice settings — wired in Phase 05.").padding()) }
        )
    }
}
