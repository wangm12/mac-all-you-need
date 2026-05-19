import Core
import CryptoKit
@testable import MacAllYouNeed
import XCTest

final class VoiceAudioAccessTests: XCTestCase {
    private var tempDir: URL!
    private var store: VoiceTrainingExampleStore!
    private var access: VoiceAudioAccess!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceAudioAccessTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try Core.Database(
            url: tempDir.appendingPathComponent("voice.sqlite"),
            migrations: ClipboardStore.migrations
        )
        let key = SymmetricKey(size: .bits256)
        store = VoiceTrainingExampleStore(
            database: db,
            deviceKey: key,
            audioRoot: tempDir.appendingPathComponent("audio", isDirectory: true)
        )
        access = VoiceAudioAccess(store: store)
    }

    override func tearDownWithError() throws {
        access = nil
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testLoadWavReturnsDecryptedBytes() throws {
        let wav = VoiceAudioCodec.encodeWAV(samples: [0, 0.5, -0.5], sampleRate: 16_000)
        let path = try store.saveEncryptedAudio(wav, id: "id-1")

        let bytes = try access.loadWav(at: path)
        XCTAssertEqual(bytes, wav)
    }

    func testLoadSamplesDecodesWAV() throws {
        let wav = VoiceAudioCodec.encodeWAV(samples: [0, 1.0, -1.0], sampleRate: 16_000)
        let path = try store.saveEncryptedAudio(wav, id: "id-2")

        let decoded = try access.loadSamples(at: path)
        XCTAssertEqual(decoded.sampleRate, 16_000)
        XCTAssertEqual(decoded.samples.count, 3)
    }
}
