@testable import MacAllYouNeed
import XCTest

final class VoiceSequentialTranscriptMergeTests: XCTestCase {
    func testMerge_joinsDistinctChunksWithSpace() {
        let result = VoiceSequentialTranscriptMerge.merge(previous: "hello", next: "world")
        XCTAssertEqual(result.text, "hello world")
        XCTAssertEqual(result.overlapCount, 0)
    }

    func testMerge_deduplicatesSuffixPrefixOverlap() {
        let result = VoiceSequentialTranscriptMerge.merge(
            previous: "今天天气很好",
            next: "天气很好啊"
        )
        XCTAssertEqual(result.text, "今天天气很好啊")
        XCTAssertGreaterThan(result.overlapCount, 0)
    }

    func testMerge_englishBoundaryOverlap() {
        let result = VoiceSequentialTranscriptMerge.merge(previous: "hello world", next: "world again")
        XCTAssertEqual(result.text, "hello world again")
        XCTAssertGreaterThan(result.overlapCount, 0)
    }

    func testMerge_chineseBoundaryOverlap() {
        let merged = VoiceSequentialTranscriptMerge.merge(
            previous: "我们正在测试长音频切分",
            next: "音频切分和合并效果"
        )
        XCTAssertEqual(merged.text, "我们正在测试长音频切分和合并效果")
    }

    func testMerge_fullSuffixContainment() {
        let result = VoiceSequentialTranscriptMerge.merge(previous: "foo bar", next: "bar")
        XCTAssertEqual(result.text, "foo bar")
        XCTAssertEqual(result.overlapCount, 3)
    }

    func testMerge_rejectsShortEnglishOverlap() {
        let result = VoiceSequentialTranscriptMerge.merge(previous: "hello", next: "low")
        XCTAssertEqual(result.text, "hello low")
        XCTAssertEqual(result.overlapCount, 0)
    }

    func testMerge_joinsCJKWithSpacePerVoxtAlphanumericsRule() {
        let result = VoiceSequentialTranscriptMerge.merge(previous: "你好", next: "世界")
        XCTAssertEqual(result.text, "你好 世界")
        XCTAssertEqual(result.overlapCount, 0)
    }

    func testMergeSequential_appliesOverlapAcrossMultipleParts() {
        let merged = VoiceSequentialTranscriptMerge.mergeSequential([
            "first chunk",
            "chunk second",
            "second final"
        ])
        XCTAssertEqual(merged, "first chunk second final")
    }
}
