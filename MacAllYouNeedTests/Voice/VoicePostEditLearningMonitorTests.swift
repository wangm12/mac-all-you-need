@testable import MacAllYouNeed
import XCTest

@MainActor
final class VoicePostEditLearningMonitorTests: XCTestCase {
    private var testSnapshot: AXTargetSnapshot!

    override func setUp() async throws {
        try await super.setUp()
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

    // MARK: - extractEditSpan unit tests

    func testExtractEditSpanIsolatesChangedWord() throws {
        let (before, after) = try XCTUnwrap(VoicePostEditLearningMonitor.extractEditSpan(
            initial: "The quick brown fox.",
            final: "The quick red fox."
        ))
        XCTAssertEqual(before, "brown")
        XCTAssertEqual(after, "red")
    }

    func testExtractEditSpanHandlesFullReplacement() throws {
        let (before, after) = try XCTUnwrap(VoicePostEditLearningMonitor.extractEditSpan(
            initial: "hello world",
            final: "Hello, world."
        ))
        // No common prefix (h vs H differ), no common suffix (d vs .)
        XCTAssertEqual(before, "hello world")
        XCTAssertEqual(after, "Hello, world.")
    }

    func testExtractEditSpanHandlesPrefixAndSuffix() throws {
        let (before, after) = try XCTUnwrap(VoicePostEditLearningMonitor.extractEditSpan(
            initial: "Existing text. hello world. More text.",
            final: "Existing text. Hello, world! More text."
        ))
        // Common suffix is " More text." (11 chars) — but '.' vs '!' differ before that,
        // so the period after "hello world" is included in the changed span.
        XCTAssertEqual(before, "hello world.")
        XCTAssertEqual(after, "Hello, world!")
        // Surrounding content "Existing text. " and " More text." do NOT appear in spans.
        XCTAssertFalse(before.contains("Existing"), "prefix leaked into before")
        XCTAssertFalse(after.contains("More"), "suffix leaked into after")
    }

    func testExtractEditSpanHandlesInsertionAtEnd() throws {
        let (before, after) = try XCTUnwrap(VoicePostEditLearningMonitor.extractEditSpan(
            initial: "hello",
            final: "hello world"
        ))
        XCTAssertEqual(before, "")
        XCTAssertEqual(after, " world")
    }

    func testExtractEditedPastedTextReturnsFinalDictationTextWithoutSurroundingDocument() {
        let finalText = VoicePostEditLearningMonitor.extractEditedPastedText(
            initial: "Before. hello world. After.",
            final: "Before. Hello, world. After.",
            pastedText: "hello world"
        )

        XCTAssertEqual(finalText, "Hello, world")
    }

    // MARK: - observe() integration tests

    func testHappyPathReturnsSampleWithExtractedEditSpan() async {
        // Simulates: paste "hello world" into a document "Before. hello world. After."
        // User edits to "Before. Hello, world. After."
        // Common suffix includes " world. After." because "world" is unchanged in position,
        // so the extracted span is "hello" → "Hello," — still useful for the LLM summarizer.
        let initial = "Before. hello world. After."
        let final_ = "Before. Hello, world. After."

        let monitor = monitor(alwaysMatches: true, valueSequence: [initial, final_])

        let draft = await monitor.observe(
            pastedText: "hello world",
            transcriptID: "tx-1",
            contextID: "ctx-1",
            isAutoSubmitContext: false,
            snapshot: testSnapshot
        )

        XCTAssertNotNil(draft)
        XCTAssertEqual(draft?.before, "hello") // greedy suffix matched " world. After."
        XCTAssertEqual(draft?.after, "Hello,")
        XCTAssertEqual(draft?.finalText, "Hello, world")
        XCTAssertEqual(draft?.quality, .high)
        XCTAssertEqual(draft?.qualityReason, "post_edit_final_text_observed")
        XCTAssertEqual(draft?.transcriptID, "tx-1")
        XCTAssertEqual(draft?.contextID, "ctx-1")
        // No surrounding content in sample
        XCTAssertFalse(draft?.before.contains("Before") ?? false)
        XCTAssertFalse(draft?.after.contains("After") ?? false)
    }

    func testSurroundingDocumentContentNotIncludedInSample() async {
        // The document has significant surrounding content around the pasted text.
        let surrounding = String(repeating: "A", count: 500)
        let initial = "\(surrounding) hello world \(surrounding)"
        let final_ = "\(surrounding) Hello. \(surrounding)"

        let monitor = monitor(alwaysMatches: true, valueSequence: [initial, final_])

        let draft = await monitor.observe(
            pastedText: "hello world",
            transcriptID: nil,
            contextID: "ctx-1",
            isAutoSubmitContext: false,
            snapshot: testSnapshot
        )

        XCTAssertNotNil(draft)
        // Surrounding content must NOT appear in either span.
        XCTAssertFalse(draft?.before.contains(surrounding) ?? false, "surrounding leaked into before")
        XCTAssertFalse(draft?.after.contains(surrounding) ?? false, "surrounding leaked into after")
        XCTAssertEqual(draft?.before, "hello world")
        XCTAssertEqual(draft?.after, "Hello.")
        XCTAssertEqual(draft?.quality, .high)
    }

    func testEditOutsidePastedTextReturnsMediumQuality() async {
        let initial = "Before. hello world. After."
        let final_ = "Changed. Hello, world. After."

        let monitor = monitor(alwaysMatches: true, valueSequence: [initial, final_])

        let draft = await monitor.observe(
            pastedText: "hello world",
            transcriptID: "tx-1",
            contextID: "ctx-1",
            isAutoSubmitContext: false,
            snapshot: testSnapshot
        )

        XCTAssertNotNil(draft)
        XCTAssertNil(draft?.finalText)
        XCTAssertEqual(draft?.quality, .medium)
        XCTAssertEqual(draft?.qualityReason, "edit_observed_without_final_text")
    }

    func testNoEditReturnsNil() async {
        let monitor = monitor(alwaysMatches: true, valueSequence: ["hello world", "hello world"])

        let draft = await monitor.observe(
            pastedText: "hello world",
            transcriptID: nil,
            contextID: "ctx-1",
            isAutoSubmitContext: false,
            snapshot: testSnapshot
        )

        XCTAssertNil(draft)
    }

    func testFocusChangeCancels() async {
        let monitor = monitor(alwaysMatches: false, valueSequence: [])

        let draft = await monitor.observe(
            pastedText: "hello world",
            transcriptID: nil,
            contextID: "ctx-1",
            isAutoSubmitContext: false,
            snapshot: testSnapshot
        )

        XCTAssertNil(draft)
    }

    func testAutoSubmitContextReturnsNil() async {
        let monitor = monitor(alwaysMatches: true, valueSequence: ["hello world", "Hello."])

        let draft = await monitor.observe(
            pastedText: "hello world",
            transcriptID: nil,
            contextID: "ctx-1",
            isAutoSubmitContext: true,
            snapshot: testSnapshot
        )

        XCTAssertNil(draft)
    }

    func testOversizedPastedTextReturnsNil() async {
        let big = String(repeating: "x", count: 3000)
        let monitor = monitor(alwaysMatches: true, valueSequence: [big, big + "!"])

        let draft = await monitor.observe(
            pastedText: big,
            transcriptID: nil,
            contextID: "ctx-1",
            isAutoSubmitContext: false,
            snapshot: testSnapshot
        )

        XCTAssertNil(draft)
    }

    func testPastedTextNeverFoundReturnsNilAfterTimeout() async {
        // With the new keep-polling-for-anchor behavior, the monitor polls
        // until the deadline rather than returning nil on the first mismatch.
        // Configure an extremely short timeout so the test completes quickly.
        var config = VoicePostEditLearningMonitor.Config()
        config.pollInterval = .milliseconds(1)
        config.idleThreshold = .milliseconds(5)
        config.maxObservationSeconds = 0 // expires immediately
        let monitor = VoicePostEditLearningMonitor(
            config: config,
            isCancelled: { false },
            matchesFocused: { _ in true },
            readCurrentValue: { _ in "completely different content" }
        )

        let draft = await monitor.observe(
            pastedText: "hello world",
            transcriptID: nil,
            contextID: "ctx-1",
            isAutoSubmitContext: false,
            snapshot: testSnapshot
        )

        XCTAssertNil(draft)
    }

    func testCancellationClosureHaltsObservation() async {
        var cancellationToggle = false
        let monitor = VoicePostEditLearningMonitor(
            config: fastConfig(),
            isCancelled: { cancellationToggle },
            matchesFocused: { _ in cancellationToggle = true; return true },
            readCurrentValue: { _ in "hello world" }
        )

        let draft = await monitor.observe(
            pastedText: "hello world",
            transcriptID: nil,
            contextID: "ctx-1",
            isAutoSubmitContext: false,
            snapshot: testSnapshot
        )

        XCTAssertNil(draft)
    }

    func testEmptyPastedTextReturnsNil() async {
        let monitor = monitor(alwaysMatches: true, valueSequence: ["x"])

        let draft = await monitor.observe(
            pastedText: "",
            transcriptID: nil,
            contextID: "ctx-1",
            isAutoSubmitContext: false,
            snapshot: testSnapshot
        )

        XCTAssertNil(draft)
    }

    // MARK: - Helpers

    private func fastConfig() -> VoicePostEditLearningMonitor.Config {
        var c = VoicePostEditLearningMonitor.Config()
        c.pollInterval = .milliseconds(1)
        c.idleThreshold = .milliseconds(5)
        c.maxObservationSeconds = 1
        return c
    }

    private func monitor(alwaysMatches: Bool, valueSequence: [String]) -> VoicePostEditLearningMonitor {
        var values = valueSequence
        return VoicePostEditLearningMonitor(
            config: fastConfig(),
            isCancelled: { false },
            matchesFocused: { _ in alwaysMatches },
            readCurrentValue: { _ in
                guard !values.isEmpty else { return values.last }
                if values.count == 1 { return values[0] }
                return values.removeFirst()
            }
        )
    }
}
