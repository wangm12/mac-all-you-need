import Core
import Foundation

struct VoiceAudioAccess {
    private let store: VoiceTrainingExampleStore

    init(store: VoiceTrainingExampleStore) {
        self.store = store
    }

    func loadWav(at path: String) throws -> Data {
        try store.loadEncryptedAudio(path: path)
    }

    func loadSamples(at path: String) throws -> VoiceAudioCodec.DecodedAudio {
        let wav = try loadWav(at: path)
        return try VoiceAudioCodec.decodeWAV(wav)
    }
}
