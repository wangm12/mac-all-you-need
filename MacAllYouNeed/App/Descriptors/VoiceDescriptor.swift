import FeatureCore
import FluidAudio
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
            assetCaches: assetCaches(),
            hotkeys: [HotkeyDescriptor(identifier: "voice.pushToTalk", displayName: "Voice push-to-talk")],
            activator: VoiceFeatureActivator()
            // settingsTabFactory and onboardingSetupFactory are nil:
            // - Settings: SettingsDetailContent wires VoiceSettingsView directly.
            // - Onboarding: OnboardingWizardView.augmented(_:) injects VoiceProviderSetupView
            //   at wizard time when the AppController reference is available.
        )
    }

    /// The two Qwen3-ASR variants the Voice provider lazily downloads.
    /// `directoryURL` delegates to FluidAudio so the cache layout stays a
    /// provider concern; we only borrow it for size reporting and uninstall.
    /// On macOS < 15, FluidAudio's Qwen3 is unavailable; the closure returns
    /// a non-existent path so `actualBytes()` reports 0 bytes.
    static func assetCaches() -> [AssetCacheDescriptor] {
        [
            AssetCacheDescriptor(
                id: "voice.qwen3.base",
                displayName: "Qwen3-ASR 0.6B int8 (~900 MB)",
                directoryURL: {
                    guard #available(macOS 15, *) else {
                        return URL(fileURLWithPath: "/dev/null/voice.qwen3.base.unavailable")
                    }
                    return Qwen3AsrModels.defaultCacheDirectory(variant: .int8)
                },
                estimatedBytes: 900_000_000,
                category: .modelWeights
            ),
            AssetCacheDescriptor(
                id: "voice.qwen3.large",
                displayName: "Qwen3-ASR 0.6B f32 (~1.75 GB)",
                directoryURL: {
                    guard #available(macOS 15, *) else {
                        return URL(fileURLWithPath: "/dev/null/voice.qwen3.large.unavailable")
                    }
                    return Qwen3AsrModels.defaultCacheDirectory(variant: .f32)
                },
                estimatedBytes: 1_750_000_000,
                category: .modelWeights
            ),
        ]
    }
}
