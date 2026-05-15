@testable import MacAllYouNeed
import XCTest

@MainActor
final class VoicePostEditLearningMonitorTests: XCTestCase {
    private var testSnapshot: AXTargetSnapshot!

    override func setUp() async throws {
        try await super.setUp()
        // Create a synthetic snapshot using the test process's own AX element.
        // The monitor's AX calls are injected via closures so this element is never
        // actually read from; we only need a non-nil AXTargetSnapshot instance.
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

    func testHappyPathReturnsSampleWhenEditDetected() async {
        let monitor = monitor(
            alwaysMatches: true,
            valueSequence: ["hello world", "Hello, world."]
        )

        let draft = await monitor.observe(
            pastedText: "hello world",
            transcriptID: "tx-1",
            contextID: "ctx-1",
            isAutoSubmitContext: false,
            snapshot: testSnapshot
        )

        XCTAssertNotNil(draft)
        XCTAssertEqual(draft?.before, "hello world")
        XCTAssertEqual(draft?.after, "Hello, world.")
        XCTAssertEqual(draft?.transcriptID, "tx-1")
        XCTAssertEqual(draft?.contextID, "ctx-1")
    }

    func testNoEditReturnsNil() async {
        let monitor = monitor(
            alwaysMatches: true,
            valueSequence: ["hello world", "hello world"]
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

    func testPastedTextNotFoundInDocumentReturnsNil() async {
        // AX value doesn't contain the pasted text (e.g. app cleared it)
        let monitor = monitor(
            alwaysMatches: true,
            valueSequence: ["completely different content", "still different"]
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
            matchesFocused: { [self] _ in
                cancellationToggle = true
                return true
            },
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

    private func monitor(
        alwaysMatches: Bool,
        valueSequence: [String]
    ) -> VoicePostEditLearningMonitor {
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
