import CryptoKit
@testable import Core
import GRDB
import XCTest

final class VoicePersonalizationStoreTests: XCTestCase {
    private var tempDir: URL!
    private var db: Core.Database!
    private var store: VoicePersonalizationStore!
    private var clock: TestClock!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoicePersonalizationStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        db = try Core.Database(
            url: tempDir.appendingPathComponent("personalization.sqlite"),
            migrations: ClipboardStore.migrations
        )
        clock = TestClock()
        store = VoicePersonalizationStore(
            database: db,
            deviceKey: SymmetricKey(size: .bits256),
            now: clock.now
        )
    }

    override func tearDownWithError() throws {
        store = nil
        db = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Contexts

    func testUpsertAndFetchGlobalContext() throws {
        let draft = VoicePersonalizationContextDraft(
            bundleID: VoicePersonalizationContext.globalBundleID,
            displayName: VoicePersonalizationContext.globalDisplayName,
            styleNotes: "Use British spelling"
        )
        let inserted = try store.upsertContext(draft)
        XCTAssertEqual(inserted.bundleID, "global")
        XCTAssertEqual(inserted.styleNotes, "Use British spelling")
        XCTAssertEqual(inserted.sampleCount, 0)
        XCTAssertNil(inserted.summary)

        let fetched = try store.fetchContext(bundleID: "global")
        XCTAssertEqual(fetched, inserted)
    }

    func testUpsertUpdatesExistingContext() throws {
        let firstInsert = try store.upsertContext(.init(bundleID: "com.apple.TextEdit", displayName: "TextEdit"))

        clock.advance(by: 1)
        let updated = try store.upsertContext(.init(
            bundleID: "com.apple.TextEdit",
            displayName: "TextEdit",
            asrModelID: "qwen3-asr-0.6b-int8",
            autoSubmitKey: .returnKey,
            customPromptOverride: "be casual"
        ))

        XCTAssertEqual(updated.id, firstInsert.id)
        XCTAssertEqual(updated.asrModelID, "qwen3-asr-0.6b-int8")
        XCTAssertEqual(updated.autoSubmitKey, .returnKey)
        XCTAssertEqual(updated.customPromptOverride, "be casual")
    }

    func testEmptyBundleIDRejected() {
        XCTAssertThrowsError(try store.upsertContext(.init(bundleID: "   ", displayName: "x"))) { error in
            XCTAssertEqual(error as? VoicePersonalizationStoreError, .emptyBundleID)
        }
    }

    func testListContextsPlacesGlobalFirst() throws {
        _ = try store.upsertContext(.init(bundleID: "com.apple.TextEdit", displayName: "TextEdit"))
        _ = try store.upsertContext(.init(bundleID: "com.apple.Safari", displayName: "Safari"))
        _ = try store.upsertContext(.init(bundleID: "global", displayName: "Global"))

        let list = try store.listContexts()
        XCTAssertEqual(list.count, 3)
        XCTAssertEqual(list.first?.bundleID, "global")
        XCTAssertEqual(list.dropFirst().map(\.bundleID), ["com.apple.Safari", "com.apple.TextEdit"])
    }

    func testDeleteContextCascadesSamples() throws {
        let context = try store.upsertContext(.init(bundleID: "com.apple.TextEdit", displayName: "TextEdit"))
        _ = try store.appendSample(.init(
            contextID: context.id,
            transcriptID: nil,
            before: "hello",
            after: "Hello.",
            diffOffset: 0,
            diffLength: 5
        ))

        try store.deleteContext(id: context.id)

        XCTAssertNil(try store.fetchContext(id: context.id))
        let recent = try? store.listRecentSamples(contextID: context.id, limit: 10)
        XCTAssertEqual(recent?.isEmpty, true)
    }

    func testClearAllEmptiesContextsAndSamples() throws {
        let ctx = try store.upsertContext(.init(bundleID: "com.apple.TextEdit", displayName: "TextEdit"))
        _ = try store.appendSample(.init(contextID: ctx.id, transcriptID: nil, before: "a", after: "b", diffOffset: 0, diffLength: 1))

        try store.clearAll()

        XCTAssertEqual(try store.listContexts(), [])
        XCTAssertEqual(try store.listRecentSamples(contextID: ctx.id, limit: 10), [])
    }

    // MARK: - Samples + encryption

    func testAppendSampleEncryptsPayloadAtRest() throws {
        let ctx = try store.upsertContext(.init(bundleID: "com.apple.TextEdit", displayName: "TextEdit"))
        let secret = "this is private"
        _ = try store.appendSample(.init(
            contextID: ctx.id,
            transcriptID: "tx-1",
            before: secret,
            after: secret + "!",
            diffOffset: 0,
            diffLength: secret.count
        ))

        let blob = try db.queue.read { conn in
            try Data.fetchOne(conn, sql: "SELECT encrypted_payload FROM voice_personalization_samples LIMIT 1")
        }
        XCTAssertNotNil(blob)
        let blobString = String(data: blob ?? Data(), encoding: .utf8) ?? ""
        XCTAssertFalse(blobString.contains(secret), "encrypted blob should not contain plaintext")
    }

    func testAppendSampleRoundTrip() throws {
        let ctx = try store.upsertContext(.init(bundleID: "com.apple.TextEdit", displayName: "TextEdit"))
        let inserted = try store.appendSample(.init(
            contextID: ctx.id,
            transcriptID: "tx-1",
            before: "hello world",
            after: "Hello, world.",
            diffOffset: 0,
            diffLength: 11
        ))

        let recent = try store.listRecentSamples(contextID: ctx.id, limit: 10)
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.before, "hello world")
        XCTAssertEqual(recent.first?.after, "Hello, world.")
        XCTAssertEqual(recent.first?.id, inserted.id)
        XCTAssertEqual(recent.first?.summarized, false)
    }

    func testSampleCountIncrementsAndDecrements() throws {
        let ctx = try store.upsertContext(.init(bundleID: "com.apple.TextEdit", displayName: "TextEdit"))
        _ = try store.appendSample(.init(contextID: ctx.id, transcriptID: nil, before: "a", after: "b", diffOffset: 0, diffLength: 1))
        _ = try store.appendSample(.init(contextID: ctx.id, transcriptID: nil, before: "c", after: "d", diffOffset: 0, diffLength: 1))

        XCTAssertEqual(try store.fetchContext(id: ctx.id)?.sampleCount, 2)

        let samples = try store.listRecentSamples(contextID: ctx.id, limit: 10)
        try store.deleteSamples(ids: [samples[0].id])
        XCTAssertEqual(try store.fetchContext(id: ctx.id)?.sampleCount, 1)
    }

    func testExpireSamplesByCount() throws {
        let ctx = try store.upsertContext(.init(bundleID: "com.apple.TextEdit", displayName: "TextEdit"))
        for i in 0 ..< 5 {
            clock.advance(by: 1)
            _ = try store.appendSample(.init(
                contextID: ctx.id,
                transcriptID: nil,
                before: "before-\(i)",
                after: "after-\(i)",
                diffOffset: 0,
                diffLength: 1
            ))
        }

        let removed = try store.expireSamplesByCount(contextID: ctx.id, max: 2)
        XCTAssertEqual(removed, 3)

        let remaining = try store.listRecentSamples(contextID: ctx.id, limit: 10)
        XCTAssertEqual(remaining.count, 2)
        XCTAssertEqual(remaining.map(\.before), ["before-4", "before-3"])
        XCTAssertEqual(try store.fetchContext(id: ctx.id)?.sampleCount, 2)
    }

    func testExpireSamplesByDate() throws {
        let ctx = try store.upsertContext(.init(bundleID: "com.apple.TextEdit", displayName: "TextEdit"))
        let fresh = try store.appendSample(.init(contextID: ctx.id, transcriptID: nil, before: "fresh", after: "x", diffOffset: 0, diffLength: 1, ttlSeconds: 60 * 60))
        let stale = try store.appendSample(.init(contextID: ctx.id, transcriptID: nil, before: "stale", after: "y", diffOffset: 0, diffLength: 1, ttlSeconds: 1))

        clock.advance(by: 10)

        let removed = try store.expireSamplesByDate()
        XCTAssertEqual(removed, 1)

        let remaining = try store.listRecentSamples(contextID: ctx.id, limit: 10)
        XCTAssertEqual(remaining.map(\.id), [fresh.id])
        XCTAssertNotEqual(remaining.first?.id, stale.id)
        XCTAssertEqual(try store.fetchContext(id: ctx.id)?.sampleCount, 1)
    }

    func testListUnsummarizedExcludesMarked() throws {
        let ctx = try store.upsertContext(.init(bundleID: "com.apple.TextEdit", displayName: "TextEdit"))
        let s1 = try store.appendSample(.init(contextID: ctx.id, transcriptID: nil, before: "a", after: "b", diffOffset: 0, diffLength: 1))
        clock.advance(by: 1)
        _ = try store.appendSample(.init(contextID: ctx.id, transcriptID: nil, before: "c", after: "d", diffOffset: 0, diffLength: 1))

        try store.markSamplesSummarized(ids: [s1.id])

        let unsummarized = try store.listUnsummarizedSamples(contextID: ctx.id)
        XCTAssertEqual(unsummarized.count, 1)
        XCTAssertEqual(unsummarized.first?.before, "c")
    }

    func testListUnsummarizedRespectsOlderThan() throws {
        let ctx = try store.upsertContext(.init(bundleID: "com.apple.TextEdit", displayName: "TextEdit"))
        let early = try store.appendSample(.init(contextID: ctx.id, transcriptID: nil, before: "early", after: "x", diffOffset: 0, diffLength: 1))
        clock.advance(by: 100)
        _ = try store.appendSample(.init(contextID: ctx.id, transcriptID: nil, before: "late", after: "y", diffOffset: 0, diffLength: 1))

        let cutoff = early.observedAt.addingTimeInterval(50)
        let beforeCutoff = try store.listUnsummarizedSamples(contextID: ctx.id, olderThan: cutoff)
        XCTAssertEqual(beforeCutoff.map(\.before), ["early"])
    }

    // MARK: - B-2: Corruption resilience

    func testCorruptedSampleIsSkippedNotBlocking() throws {
        let ctx = try store.upsertContext(.init(bundleID: "com.apple.TextEdit", displayName: "TextEdit"))
        let good = try store.appendSample(.init(
            contextID: ctx.id, transcriptID: nil,
            before: "hello", after: "Hello.", diffOffset: 0, diffLength: 5
        ))

        // Insert a deliberately corrupt encrypted_payload that will fail to decrypt
        // (random bytes are not a valid AES-GCM envelope).
        try db.queue.write { conn in
            try conn.execute(sql: """
                INSERT INTO voice_personalization_samples (
                    id, context_id, transcript_id, encrypted_payload,
                    observed_at, expires_at, summarized
                ) VALUES (?, ?, NULL, ?, ?, ?, 0)
            """, arguments: [
                "corrupt-id",
                ctx.id,
                Data([0x00, 0x01, 0x02, 0x03]),
                Int64(Date().timeIntervalSince1970 * 1000),
                Int64(Date().addingTimeInterval(60 * 60).timeIntervalSince1970 * 1000)
            ])
        }

        // listRecentSamples must skip the corrupt row and still return the good one.
        let recent = try store.listRecentSamples(contextID: ctx.id, limit: 10)
        XCTAssertEqual(recent.count, 1, "good sample must remain readable when a sibling row is corrupt")
        XCTAssertEqual(recent.first?.id, good.id)

        // listUnsummarizedSamples must also skip the corrupt row.
        let unsummarized = try store.listUnsummarizedSamples(contextID: ctx.id)
        XCTAssertEqual(unsummarized.count, 1)
        XCTAssertEqual(unsummarized.first?.id, good.id)
    }

    // MARK: - Summary

    func testSetAndReadSummary() throws {
        let ctx = try store.upsertContext(.init(bundleID: "com.apple.TextEdit", displayName: "TextEdit"))
        try store.setSummary(contextID: ctx.id, summary: "Casual tone, no fillers.", sourceSampleCount: 12)

        let refreshed = try store.fetchContext(id: ctx.id)
        XCTAssertEqual(refreshed?.summary, "Casual tone, no fillers.")
        XCTAssertEqual(refreshed?.summarySourceCount, 12)
        XCTAssertNotNil(refreshed?.summaryGeneratedAt)
    }

    func testSummaryEncryptedAtRest() throws {
        let ctx = try store.upsertContext(.init(bundleID: "com.apple.TextEdit", displayName: "TextEdit"))
        let secret = "summary contains a private detail"
        try store.setSummary(contextID: ctx.id, summary: secret, sourceSampleCount: 1)

        let blob = try db.queue.read { conn in
            try Data.fetchOne(conn, sql: "SELECT encrypted_summary FROM voice_personalization_contexts WHERE id = ?", arguments: [ctx.id])
        }
        XCTAssertNotNil(blob)
        let blobString = String(data: blob ?? Data(), encoding: .utf8) ?? ""
        XCTAssertFalse(blobString.contains(secret))
    }

    func testClearSummary() throws {
        let ctx = try store.upsertContext(.init(bundleID: "com.apple.TextEdit", displayName: "TextEdit"))
        try store.setSummary(contextID: ctx.id, summary: "x", sourceSampleCount: 5)
        try store.clearSummary(contextID: ctx.id)

        let refreshed = try store.fetchContext(id: ctx.id)
        XCTAssertNil(refreshed?.summary)
        XCTAssertEqual(refreshed?.summarySourceCount, 0)
        XCTAssertNil(refreshed?.summaryGeneratedAt)
    }
}

// Test helpers ---------------------------------------------------------------

private final class TestClock {
    private var current: Date

    init(start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        current = start
    }

    func now() -> Date { current }

    func advance(by seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
    }
}
