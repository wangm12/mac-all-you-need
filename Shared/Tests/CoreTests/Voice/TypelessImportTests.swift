@testable import Core
import CryptoKit
import GRDB
import XCTest

final class TypelessImportTests: XCTestCase {
    private var tempDir: URL!
    private var typelessDBURL: URL!
    private var maynDB: Core.Database!
    private var key: SymmetricKey!
    private var transcripts: VoiceTranscriptStore!
    private var training: VoiceTrainingExampleStore!
    private var recordingsRoot: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TypelessImportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        typelessDBURL = tempDir.appendingPathComponent("typeless.db")
        try Self.seedTypelessFixture(at: typelessDBURL)

        recordingsRoot = tempDir.appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: recordingsRoot, withIntermediateDirectories: true)
        let oggID = "11111111-1111-1111-1111-111111111111"
        FileManager.default.createFile(
            atPath: recordingsRoot.appendingPathComponent("\(oggID).ogg").path,
            contents: Data([0x4F, 0x67, 0x67, 0x53])
        )

        maynDB = try Core.Database(
            url: tempDir.appendingPathComponent("clipboard.sqlite"),
            migrations: ClipboardStore.migrations
        )
        key = SymmetricKey(size: .bits256)
        transcripts = VoiceTranscriptStore(database: maynDB)
        training = VoiceTrainingExampleStore(
            database: maynDB,
            deviceKey: key,
            audioRoot: tempDir.appendingPathComponent("voice-training-audio", isDirectory: true)
        )
    }

    override func tearDownWithError() throws {
        transcripts = nil
        training = nil
        maynDB = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testReaderFiltersTablesAndOrdersNewestFirst() throws {
        let records = try TypelessHistoryReader(databaseURL: typelessDBURL).loadRecords()
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].id, "22222222-2222-2222-2222-222222222222")
        XCTAssertEqual(records[0].sourceTable, .historyV2)
        XCTAssertEqual(records[1].id, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(records[1].sourceTable, .history)
        XCTAssertNil(records.first { $0.id == "44444444-4444-4444-4444-444444444444" })
    }

    func testLanguageMapperDetectsMixed() {
        XCTAssertEqual(
            TypelessLanguageMapper.map(detectedLanguage: "en-US", languagesJSON: #"["zh-CN","en"]"#),
            .mixed
        )
    }

    func testDryRunCountsWithoutWrites() throws {
        let report = try makeImporter(converter: MockTypelessAudioConverter()).importAll(
            options: .init(dryRun: true, skipAudio: true)
        )
        XCTAssertEqual(report.scanned, 2)
        XCTAssertEqual(report.imported, 2)
        XCTAssertEqual(try transcripts.listRecent(limit: 10).count, 0)
    }

    func testSkipExistingTranscriptIDs() throws {
        _ = try transcripts.save(.init(
            startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2),
            rawText: "existing",
            cleanedText: "existing",
            appBundleID: nil,
            language: .unknown,
            modelIdentifier: "seed",
            audioPath: nil
        ), existingID: "11111111-1111-1111-1111-111111111111")

        let report = try makeImporter(converter: MockTypelessAudioConverter()).importAll(
            options: .init(skipAudio: true)
        )
        XCTAssertEqual(report.skippedExisting, 1)
        XCTAssertEqual(report.imported, 1)
    }

    func testImportAudioWhenOGGPresent() throws {
        let report = try makeImporter(converter: MockTypelessAudioConverter()).importAll(
            options: .init(skipAudio: false, limit: 2)
        )
        XCTAssertEqual(report.audioImported, 1)
        let legacy = try XCTUnwrap(transcripts.fetch(id: "11111111-1111-1111-1111-111111111111"))
        XCTAssertNotNil(legacy.audioPath)
    }

    func testImportPersistsTranscriptAndTrainingExample() throws {
        let report = try makeImporter(converter: MockTypelessAudioConverter()).importAll(
            options: .init(skipAudio: false, limit: 1)
        )
        XCTAssertEqual(report.imported, 1)
        XCTAssertEqual(report.audioImported, 0)

        let id = "22222222-2222-2222-2222-222222222222"
        let transcript = try XCTUnwrap(transcripts.fetch(id: id))
        XCTAssertEqual(transcript.cleanedText, "Completed v2 line.")
        XCTAssertEqual(transcript.modelIdentifier, TypelessLanguageMapper.typelessImportModelIdentifier)
        XCTAssertNil(transcript.audioPath)

        let example = try XCTUnwrap(training.fetch(transcriptID: id))
        XCTAssertEqual(example.finalText, "Completed v2 line.")
        XCTAssertEqual(example.qualityReason, "typeless_import")
    }

    private func makeImporter(converter: TypelessAudioConverting?) -> TypelessHistoryImporter {
        TypelessHistoryImporter(
            reader: TypelessHistoryReader(databaseURL: typelessDBURL),
            transcriptStore: transcripts,
            trainingExampleStore: training,
            recordingsRoot: recordingsRoot,
            audioConverter: converter
        )
    }

    private static func seedTypelessFixture(at url: URL) throws {
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE history (
                    id TEXT PRIMARY KEY NOT NULL,
                    refined_text TEXT,
                    edited_text TEXT,
                    audio_local_path TEXT,
                    status TEXT,
                    duration REAL,
                    created_at TEXT,
                    focused_app_bundle_id TEXT,
                    detected_language TEXT,
                    languages TEXT
                );
                CREATE TABLE history_v2 (
                    id TEXT PRIMARY KEY NOT NULL,
                    refined_text TEXT,
                    status TEXT,
                    duration REAL,
                    created_at TEXT,
                    audio_local_path TEXT
                );
            """)
            try db.execute(sql: """
                INSERT INTO history VALUES (
                    '11111111-1111-1111-1111-111111111111',
                    'Legacy transcript line.',
                    NULL,
                    '11111111-1111-1111-1111-111111111111.ogg',
                    'transcript',
                    2.5,
                    '2026-05-01T10:00:00',
                    'com.apple.TextEdit',
                    'en',
                    NULL
                );
                INSERT INTO history VALUES (
                    '33333333-3333-3333-3333-333333333333',
                    '   ',
                    NULL,
                    NULL,
                    'transcript',
                    1.0,
                    '2026-05-02T10:00:00',
                    NULL,
                    NULL,
                    NULL
                );
                INSERT INTO history VALUES (
                    '44444444-4444-4444-4444-444444444444',
                    'Dismissed row',
                    NULL,
                    NULL,
                    'dismissed',
                    1.0,
                    '2026-05-03T10:00:00',
                    NULL,
                    NULL,
                    NULL
                );
                INSERT INTO history_v2 VALUES (
                    '22222222-2222-2222-2222-222222222222',
                    'Completed v2 line.',
                    'completed',
                    3.0,
                    '2026-05-10T12:00:00',
                    NULL
                );
            """)
        }
    }
}

private struct MockTypelessAudioConverter: TypelessAudioConverting {
    func convertOGGToWAV(oggURL: URL) throws -> Data {
        VoiceAudioCodec.encodeWAV(samples: [0, 0.1, -0.1], sampleRate: 16_000)
    }
}
