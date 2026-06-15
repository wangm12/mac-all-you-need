import Core
import Foundation

final class GroqASRKeyStore {
    private let cloudKeyStore: VoiceCloudASRKeyStore

    init(keychain: KeychainBackend) {
        cloudKeyStore = VoiceCloudASRKeyStore(keychain: keychain)
    }

    func apiKey() throws -> String? {
        try cloudKeyStore.apiKey(for: .groq)
    }

    func saveAPIKey(_ apiKey: String) throws {
        try cloudKeyStore.saveAPIKey(apiKey, for: .groq)
    }

    func deleteAPIKey() throws {
        try cloudKeyStore.deleteAPIKey(for: .groq)
    }
}

final class VoiceCloudASRKeyStore {
    private let keychain: KeychainBackend

    init(keychain: KeychainBackend) {
        self.keychain = keychain
    }

    func apiKey(for providerKind: VoiceASRProviderKind) throws -> String? {
        guard let data = try keychain.get(account(for: providerKind)),
              let key = String(data: data, encoding: .utf8),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return key
    }

    func saveAPIKey(_ apiKey: String, for providerKind: VoiceASRProviderKind) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try deleteAPIKey(for: providerKind)
            return
        }
        try keychain.set(Data(trimmed.utf8), for: account(for: providerKind))
    }

    func deleteAPIKey(for providerKind: VoiceASRProviderKind) throws {
        try keychain.delete(account(for: providerKind))
    }

    private func account(for providerKind: VoiceASRProviderKind) -> String {
        switch providerKind {
        case .local:
            "voice.asr.local.api-key.v1"
        case .groq:
            "voice.asr.groq.api-key.v1"
        case .elevenLabs:
            "voice.asr.elevenlabs.api-key.v1"
        case .openAITranscribe, .openAIRealtime:
            // Realtime shares the OpenAI key — users only need one key for both modes.
            "voice.asr.openai.api-key.v1"
        case .deepgram:
            "voice.asr.deepgram.api-key.v1"
        }
    }
}
