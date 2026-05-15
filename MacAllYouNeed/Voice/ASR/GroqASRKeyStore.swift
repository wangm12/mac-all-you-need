import Core
import Foundation

final class GroqASRKeyStore {
    private let keychain: KeychainBackend
    private let account = "voice.asr.groq.api-key.v1"

    init(keychain: KeychainBackend) {
        self.keychain = keychain
    }

    func apiKey() throws -> String? {
        guard let data = try keychain.get(account),
              let key = String(data: data, encoding: .utf8),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return key
    }

    func saveAPIKey(_ apiKey: String) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try keychain.delete(account)
            return
        }
        try keychain.set(Data(trimmed.utf8), for: account)
    }

    func deleteAPIKey() throws {
        try keychain.delete(account)
    }
}
