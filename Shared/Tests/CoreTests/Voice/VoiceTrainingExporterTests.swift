import CryptoKit
import Foundation
@testable import Core
import XCTest

final class VoiceTrainingExporterTests: XCTestCase {
    private var tempDir: URL!
    private var store: VoiceTrainingExampleStore!
    private var transcripts: VoiceTranscriptStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceExportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try Database(
            url: tempDir.appendingPathComponent("db.sqlite"),
            migrations: ClipboardStore.migrations
        )
        let audioRoot = tempDir.appendingPathComponent("audio", isDirectory: true)
        store = VoiceTrainingExampleStore(
            database: db,
            deviceKey: SymmetricKey(size: .bits256),
            audioRoot: audioRoot
        )
        transcripts = VoiceTranscriptStore(database: db)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testExportWritesJSONLAndWAV() throws {
        let transcript = try saveTranscript()
        let wav = makeWAV(durationSeconds: 2)
        let audioPath = try store.saveEncryptedAudio(wav, id: "audio-1")
        _ = try store.save(VoiceTrainingExampleDraft(
            transcriptID: transcript.id,
            rawText: "hello",
            cleanedText: "Hello",
            finalText: "Hello.",
            appBundleID: "com.apple.TextEdit",
            language: .english,
            modelIdentifier: "test-asr",
            audioPath: audioPath,
            quality: .high,
            qualityReason: "post_edit_final_text_observed"
        ))

        let archive = tempDir.appendingPathComponent("export.tar.gz")
        let summary = try VoiceTrainingExporter(store: store).export(to: archive)
        XCTAssertEqual(summary.exportedCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
    }

    func testExportSkipsMediumQualityByDefault() throws {
        let transcript = try saveTranscript()
        let wav = makeWAV(durationSeconds: 2)
        let audioPath = try store.saveEncryptedAudio(wav, id: "audio-2")
        _ = try store.save(VoiceTrainingExampleDraft(
            transcriptID: transcript.id,
            rawText: "hi",
            cleanedText: "Hi",
            finalText: "Hi",
            appBundleID: nil,
            language: .english,
            modelIdentifier: "test-asr",
            audioPath: audioPath,
            quality: .medium,
            qualityReason: "awaiting_post_edit_verification"
        ))

        let archive = tempDir.appendingPathComponent("skip.tar.gz")
        XCTAssertThrowsError(try VoiceTrainingExporter(store: store).export(to: archive)) { error in
            XCTAssertEqual(error as? VoiceTrainingExporterError, .noEligibleExamples)
        }
    }

    private func saveTranscript() throws -> VoiceTranscript {
        try transcripts.save(.init(
            startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2),
            rawText: "raw",
            cleanedText: "clean",
            appBundleID: nil,
            language: .english,
            modelIdentifier: "qwen3",
            audioPath: nil
        ))
    }

    private func makeWAV(durationSeconds: Int) -> Data {
        let sampleRate: UInt32 = 16_000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let dataSize = byteRate * UInt32(durationSeconds)
        var data = Data()
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // RIFF
        var chunkSize = UInt32(36) + dataSize
        data.append(Data(bytes: &chunkSize, count: 4))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        var subchunk1Size: UInt32 = 16
        data.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat: UInt16 = 1
        data.append(Data(bytes: &audioFormat, count: 2))
        var ch = channels
        data.append(Data(bytes: &ch, count: 2))
        var sr = sampleRate
        data.append(Data(bytes: &sr, count: 4))
        var br = byteRate
        data.append(Data(bytes: &br, count: 4))
        var blockAlign = channels * bitsPerSample / 8
        data.append(Data(bytes: &blockAlign, count: 2))
        var bps = bitsPerSample
        data.append(Data(bytes: &bps, count: 2))
        data.append(contentsOf: "data".utf8)
        var ds = dataSize
        data.append(Data(bytes: &ds, count: 4))
        data.append(Data(count: Int(dataSize)))
        return data
    }
}
