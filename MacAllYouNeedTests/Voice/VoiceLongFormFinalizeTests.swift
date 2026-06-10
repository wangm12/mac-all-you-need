@testable import MacAllYouNeed
import XCTest

final class VoiceLongFormFinalizeTests: XCTestCase {
    private let sampleRate = 16_000.0

    func testTailPlan_shortRecordingUsesPendingOnly() {
        let tenSeconds = Int(10 * sampleRate)
        let plan = VoiceLongFormASRPlanning.tailTranscriptionPlan(
            totalCapturedCount: tenSeconds,
            capturedSampleRate: sampleRate,
            committedPartCount: 0,
            pendingCount: tenSeconds
        )
        XCTAssertFalse(plan.useWidenedTail)
        XCTAssertEqual(plan.tailSampleCount, tenSeconds)
    }

    func testTailPlan_mediumRecordingWithoutCommitsUsesPendingOnly() {
        let twentySeconds = Int(20 * sampleRate)
        let plan = VoiceLongFormASRPlanning.tailTranscriptionPlan(
            totalCapturedCount: twentySeconds,
            capturedSampleRate: sampleRate,
            committedPartCount: 0,
            pendingCount: twentySeconds
        )
        XCTAssertFalse(plan.useWidenedTail)
        XCTAssertEqual(plan.tailSampleCount, twentySeconds)
    }

    func testTailPlan_longRecordingWithCommitsUsesWidenedTail() {
        let thirtySeconds = Int(30 * sampleRate)
        let pending = Int(5 * sampleRate)
        let plan = VoiceLongFormASRPlanning.tailTranscriptionPlan(
            totalCapturedCount: thirtySeconds,
            capturedSampleRate: sampleRate,
            committedPartCount: 1,
            pendingCount: pending
        )
        XCTAssertTrue(plan.useWidenedTail)
        XCTAssertEqual(plan.tailSampleCount, VoiceLongFormASRPlanning.quickPassWindowSamples)
    }

    func testTailPlan_veryLongRecordingCapsWidenedTailAtCapturedLength() {
        let ninetySeconds = Int(90 * sampleRate)
        let pending = Int(15 * sampleRate)
        let plan = VoiceLongFormASRPlanning.tailTranscriptionPlan(
            totalCapturedCount: ninetySeconds,
            capturedSampleRate: sampleRate,
            committedPartCount: 3,
            pendingCount: pending
        )
        XCTAssertTrue(plan.useWidenedTail)
        XCTAssertEqual(plan.tailSampleCount, min(VoiceLongFormASRPlanning.quickPassWindowSamples, ninetySeconds))
    }

    func testTailMergePolicy_rejectsEmptyWidenedTail() {
        XCTAssertFalse(
            VoiceLongFormTailMergePolicy.shouldUseWidenedTailMerge(
                pendingTailText: "pending tail",
                widenedTailText: "   ",
                committedTextBeforeTail: "committed"
            )
        )
    }

    func testTailMergePolicy_rejectsInteriorSharedWindowWithoutTextOverlap() {
        XCTAssertFalse(
            VoiceLongFormTailMergePolicy.shouldUseWidenedTailMerge(
                pendingTailText: "bbbbzzzz",
                widenedTailText: "YYYYXXXXbbbbzzzz",
                committedTextBeforeTail: "aaaaXXXXbbbb"
            )
        )
    }

    func testTailMergePolicy_acceptsCleanWidenedMerge() {
        XCTAssertTrue(
            VoiceLongFormTailMergePolicy.shouldUseWidenedTailMerge(
                pendingTailText: "world",
                widenedTailText: "world again",
                committedTextBeforeTail: "hello"
            )
        )
    }
}
