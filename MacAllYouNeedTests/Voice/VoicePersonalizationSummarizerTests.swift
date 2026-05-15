import Core
import CryptoKit
@testable import MacAllYouNeed
import XCTest

final class VoicePersonalizationSummarizerTests: XCTestCase {
    private var tempDir: URL!
    private var store: VoicePersonalizationStore!
    private var contextID: String!
    private var clock: TestSummarizerClock!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SummarizerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        clock = TestSummarizerClock()
        let db = try Core.Database(
            url: tempDir.appendingPathComponent("db.sqlite"),
            migrations: ClipboardStore.migrations
        )
        store = VoicePersonalizationStore(
            database: db,
            deviceKey: SymmetricKey(size: .bits256),
            now: clock.now
        )
        let ctx = try store.upsertContext(.init(bundleID: "com.apple.TextEdit", displayName: "TextEdit"))
        contextID = ctx.id
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testRunsWhenCountThresholdMet() async throws {
        try seedSamples(count: 20)

        var called = false
        let summarizer = makeSummarizer { called = true; return "casual, no fillers" }

        await summarizer.maybeRun(contextID: contextID)
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertTrue(called, "provider should be called when count threshold met")
        let ctx = try store.fetchContext(id: contextID)
        XCTAssertNotNil(ctx?.summary)
        XCTAssertEqual(ctx?.summarySourceCount, 20)
    }

    func testRunsWhenOldSampleExists() async throws {
        try seedSamples(count: 1)
        clock.advance(by: 8 * 86400)

        var called = false
        let summarizer = makeSummarizer { called = true; return "formal tone" }

        await summarizer.maybeRun(contextID: contextID)
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertTrue(called)
    }

    func testSkipsWhenThresholdNotMet() async throws {
        try seedSamples(count: 5)

        var called = false
        let summarizer = makeSummarizer { called = true; return "x" }

        await summarizer.maybeRun(contextID: contextID)
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertFalse(called, "provider must not be called below threshold")
    }

    func testSkipsWhenLearningDisabled() async throws {
        try seedSamples(count: 20)

        var called = false
        let summarizer = makeSummarizer(
            settings: VoicePersonalizationSettings(learnFromEditsEnabled: false),
            handler: { called = true; return "x" }
        )

        await summarizer.maybeRun(contextID: contextID)
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertFalse(called)
    }

    func testSkipsWhenProviderUnavailable() async throws {
        try seedSamples(count: 20)

        let summarizer = VoicePersonalizationSummarizer(
            store: store,
            settings: { .default },
            makeProvider: { nil },
            now: clock.now
        )

        await summarizer.maybeRun(contextID: contextID)
        try await Task.sleep(for: .milliseconds(150))

        let ctx = try store.fetchContext(id: contextID)
        XCTAssertNil(ctx?.summary)
    }

    func testInFlightGuardPreventsConcurrentRuns() async throws {
        try seedSamples(count: 20)

        var callCount = 0
        let summarizer = makeSummarizer {
            callCount += 1
            try? await Task.sleep(for: .milliseconds(100))
            return "summary"
        }

        await summarizer.maybeRun(contextID: contextID)
        await summarizer.maybeRun(contextID: contextID)
        await summarizer.maybeRun(contextID: contextID)
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(callCount, 1)
    }

    func testMarksSamplesAsSummarized() async throws {
        try seedSamples(count: 20)

        let summarizer = makeSummarizer { "done" }
        await summarizer.maybeRun(contextID: contextID)
        try await Task.sleep(for: .milliseconds(300))

        let remaining = try store.listUnsummarizedSamples(contextID: contextID)
        XCTAssertTrue(remaining.isEmpty)
    }

    // MARK: - Helpers

    private func seedSamples(count: Int) throws {
        for i in 0 ..< count {
            clock.advance(by: 1)
            _ = try store.appendSample(.init(
                contextID: contextID,
                transcriptID: nil,
                before: "sample \(i)",
                after: "Sample \(i).",
                diffOffset: 0,
                diffLength: 8
            ))
        }
    }

    private func makeSummarizer(
        settings: VoicePersonalizationSettings = .default,
        handler: @escaping () async throws -> String
    ) -> VoicePersonalizationSummarizer {
        let provider = MockTextGenerationProvider(handler: handler)
        return VoicePersonalizationSummarizer(
            store: store,
            settings: { settings },
            makeProvider: { provider },
            now: clock.now
        )
    }
}

private final class MockTextGenerationProvider: VoiceTextGenerationProvider {
    let providerIdentifier = "mock"
    private let handler: () async throws -> String

    init(handler: @escaping () async throws -> String) {
        self.handler = handler
    }

    func generate(systemPrompt _: String, userText _: String) async throws -> String {
        try await handler()
    }
}

private final class TestSummarizerClock {
    private var current: Date = Date(timeIntervalSince1970: 1_700_000_000)
    func now() -> Date { current }
    func advance(by seconds: TimeInterval) { current = current.addingTimeInterval(seconds) }
}
