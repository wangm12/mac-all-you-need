@testable import MacAllYouNeed
import XCTest

final class VoiceLongFormASRPlanningTests: XCTestCase {
    func testSamplesToCommit_nilUntilSegmentFull() {
        let maxSegment = VoiceLongFormASRPlanning.maxSegmentSamples
        XCTAssertNil(VoiceLongFormASRPlanning.samplesToCommit(pendingCount: maxSegment - 1))
        XCTAssertEqual(
            VoiceLongFormASRPlanning.samplesToCommit(pendingCount: maxSegment),
            VoiceLongFormASRPlanning.commitLengthSamples
        )
    }

    func testBatchStride_isSegmentMinusOverlap() {
        XCTAssertEqual(
            VoiceLongFormASRPlanning.batchStrideSamples,
            VoiceLongFormASRPlanning.maxSegmentSamples - VoiceLongFormASRPlanning.overlapSamples
        )
    }

    func testMergeSequential_handlesOverlappingBatchChunks() {
        let merged = VoiceSequentialTranscriptMerge.mergeSequential([
            "今天我们讨论项目进度",
            "项目进度和下一步计划",
            "下一步计划需要确认"
        ])
        XCTAssertEqual(merged, "今天我们讨论项目进度和下一步计划需要确认")
    }
}
