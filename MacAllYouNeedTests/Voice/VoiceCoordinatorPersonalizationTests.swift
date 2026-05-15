import ApplicationServices
import Core
import CryptoKit
@testable import MacAllYouNeed
import XCTest

/// Integration tests for the personalization wiring in VoiceCoordinator.
/// These use a real in-memory store, an injectable monitor, and a spy on
/// the store's sample count to assert observable behaviour without running
/// the full audio/ASR pipeline.
@MainActor
final class VoiceCoordinatorPersonalizationTests: XCTestCase {
    private var store: VoicePersonalizationStore!
    private var tempDir: URL!
    private var testSnapshot: AXTargetSnapshot!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoordPersonTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try Core.Database(
            url: tempDir.appendingPathComponent("db.sqlite"),
            migrations: ClipboardStore.migrations
        )
        store = VoicePersonalizationStore(
            database: db,
            deviceKey: SymmetricKey(size: .bits256)
        )
        // Synthetic snapshot using the test process's own AX element.
        // The monitor is fully injected so the real AX APIs are never called.
        let element = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let meta = AXTargetMetadata(
            bundleID: "com.apple.TextEdit",
            pid: ProcessInfo.processInfo.processIdentifier,
            role: "AXTextArea",
            subrole: nil,
            isEditable: true
        )
        testSnapshot = AXTargetSnapshot(metadata: meta, element: element)
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - C1: Privacy filter enforced

    func testSecureFieldSnapshotDoesNotCreateSample() async throws {
        // A snapshot whose metadata has subrole == AXSecureTextField must be rejected
        // by VoicePersonalizationPrivacyFilter before the monitor is ever started.
        let secureElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let secureMeta = AXTargetMetadata(
            bundleID: "com.apple.TextEdit",
            pid: ProcessInfo.processInfo.processIdentifier,
            role: "AXTextField",
            subrole: "AXSecureTextField",
            isEditable: true
        )
        let secureSnapshot = AXTargetSnapshot(metadata: secureMeta, element: secureElement)

        let coordinator = makeCoordinator(pastedText: "hello world", editValue: "Hello, world.")
        callStartLearningMonitor(
            coordinator,
            pastedText: "hello world",
            appBundleID: "com.apple.TextEdit",
            snapshot: secureSnapshot
        )
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(sampleCount(bundleID: "com.apple.TextEdit"), 0,
                       "secure field must be rejected before monitor starts")
    }

    func testDenyListedBundleDoesNotCreateSample() async throws {
        let denyElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let denyMeta = AXTargetMetadata(
            bundleID: "com.1password.1password",
            pid: ProcessInfo.processInfo.processIdentifier,
            role: "AXTextArea",
            subrole: nil,
            isEditable: true
        )
        let denySnapshot = AXTargetSnapshot(metadata: denyMeta, element: denyElement)

        let coordinator = makeCoordinator(pastedText: "hello", editValue: "pw123")
        callStartLearningMonitor(
            coordinator,
            pastedText: "hello",
            appBundleID: "com.1password.1password",
            snapshot: denySnapshot
        )
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(sampleCount(bundleID: "com.1password.1password"), 0,
                       "deny-listed bundle must not produce samples")
    }

    // MARK: - C2: First-use context creation

    func testFirstDictationCreatesPerAppContext() async throws {
        XCTAssertNil(try? store.fetchContext(bundleID: "com.apple.TextEdit"),
                     "precondition: no TextEdit context yet")

        let coordinator = makeCoordinator(pastedText: "hello world", editValue: "Hello, world.")
        callStartLearningMonitor(
            coordinator,
            pastedText: "hello world",
            appBundleID: "com.apple.TextEdit",
            snapshot: testSnapshot
        )
        try await Task.sleep(for: .milliseconds(100))

        let ctx = try store.fetchContext(bundleID: "com.apple.TextEdit")
        XCTAssertNotNil(ctx, "per-app context must be created on first dictation")
        XCTAssertEqual(ctx?.sampleCount, 1)
    }

    func testSampleStoredUnderPerAppContextNotGlobal() async throws {
        // Even if a global context exists, the sample goes to the app context.
        _ = try store.upsertContext(.init(
            bundleID: VoicePersonalizationContext.globalBundleID,
            displayName: "Global"
        ))

        let coordinator = makeCoordinator(pastedText: "hello world", editValue: "Hello, world.")
        callStartLearningMonitor(
            coordinator,
            pastedText: "hello world",
            appBundleID: "com.apple.TextEdit",
            snapshot: testSnapshot
        )
        try await Task.sleep(for: .milliseconds(100))

        let globalCtx = try store.fetchContext(bundleID: VoicePersonalizationContext.globalBundleID)
        XCTAssertEqual(globalCtx?.sampleCount, 0, "global context must stay empty")

        let appCtx = try store.fetchContext(bundleID: "com.apple.TextEdit")
        XCTAssertEqual(appCtx?.sampleCount, 1, "sample must go to per-app context")
    }

    // MARK: - I3: Disabled context blocks learning

    func testDisabledAppContextBlocksLearning() async throws {
        _ = try store.upsertContext(.init(
            bundleID: "com.apple.TextEdit",
            displayName: "TextEdit",
            enabled: false
        ))
        // Also create global so there's somewhere to fall back to.
        _ = try store.upsertContext(.init(
            bundleID: VoicePersonalizationContext.globalBundleID,
            displayName: "Global"
        ))

        let coordinator = makeCoordinator(pastedText: "hello world", editValue: "Hello.")
        callStartLearningMonitor(
            coordinator,
            pastedText: "hello world",
            appBundleID: "com.apple.TextEdit",
            snapshot: testSnapshot
        )
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(sampleCount(bundleID: "com.apple.TextEdit"), 0,
                       "disabled app context must block learning")
        XCTAssertEqual(sampleCount(bundleID: VoicePersonalizationContext.globalBundleID), 0,
                       "global must not receive samples when app is explicitly disabled")
    }

    // MARK: - I4: Retention limits enforced on append

    func testSampleCountCappedAtMaxAfterAppend() async throws {
        let maxSamples = 3
        var settings = VoicePersonalizationSettings.default
        settings.rollingCacheMaxSamples = maxSamples

        let ctx = try store.upsertContext(.init(bundleID: "com.apple.TextEdit", displayName: "TextEdit"))
        // Seed 3 samples already at the limit.
        for i in 0 ..< maxSamples {
            _ = try store.appendSample(.init(
                contextID: ctx.id,
                transcriptID: nil,
                before: "old \(i)",
                after: "Old \(i).",
                diffOffset: 0,
                diffLength: 5
            ))
        }
        XCTAssertEqual(sampleCount(bundleID: "com.apple.TextEdit"), maxSamples)

        let coordinator = makeCoordinator(pastedText: "hello world", editValue: "Hello, world.", settings: settings)
        callStartLearningMonitor(
            coordinator,
            pastedText: "hello world",
            appBundleID: "com.apple.TextEdit",
            snapshot: testSnapshot
        )
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(sampleCount(bundleID: "com.apple.TextEdit"), maxSamples,
                       "count must stay at max after expiry runs post-append")
    }

    // MARK: - Helpers

    private func makeCoordinator(
        pastedText: String = "hello world",
        editValue: String,
        settings: VoicePersonalizationSettings = .default
    ) -> VoiceCoordinator {
        // Monitor value sequence: first read returns the pasted text (anchor confirmation),
        // then the edited value (triggers idle detection and sample capture).
        var valueSeq = [pastedText, editValue]
        let monitor = VoicePostEditLearningMonitor(
            config: fastMonitorConfig(),
            isCancelled: { false },
            matchesFocused: { _ in true },
            readCurrentValue: { _ in
                guard !valueSeq.isEmpty else { return valueSeq.last }
                if valueSeq.count == 1 { return valueSeq[0] }
                return valueSeq.removeFirst()
            }
        )
        return VoiceCoordinator(
            transcripts: VoiceTranscriptStore(database: try! Core.Database(
                url: tempDir.appendingPathComponent("transcripts-\(UUID().uuidString).sqlite"),
                migrations: ClipboardStore.migrations
            )),
            personalizationStore: store,
            personalizationSettings: { settings },
            learningMonitor: monitor
        )
    }

    private func callStartLearningMonitor(
        _ coordinator: VoiceCoordinator,
        pastedText: String,
        appBundleID: String?,
        snapshot: AXTargetSnapshot
    ) {
        coordinator.startLearningMonitor(
            pastedText: pastedText,
            transcriptID: "test-tx",
            appBundleID: appBundleID,
            isAutoSubmit: false,
            snapshot: snapshot
        )
    }

    private func sampleCount(bundleID: String) -> Int {
        (try? store.fetchContext(bundleID: bundleID))?.sampleCount ?? 0
    }

    private func fastMonitorConfig() -> VoicePostEditLearningMonitor.Config {
        var c = VoicePostEditLearningMonitor.Config()
        c.pollInterval = .milliseconds(1)
        c.idleThreshold = .milliseconds(5)
        c.maxObservationSeconds = 1
        return c
    }
}
