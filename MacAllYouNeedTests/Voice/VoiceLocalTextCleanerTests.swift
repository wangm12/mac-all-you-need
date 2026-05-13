@testable import MacAllYouNeed
import XCTest

final class VoiceLocalTextCleanerTests: XCTestCase {
    func testRemovesStandaloneFillersAndConvertsSpokenDigitSequence() {
        let input = "test一二三四，test，帮我修改一下这个test。嗯，啊，ok。"

        XCTAssertEqual(
            VoiceLocalTextCleaner.clean(input),
            "test1234，test，帮我修改一下这个test。ok。"
        )
    }

    func testPreservesNonDigitChineseNumberPhrases() {
        XCTAssertEqual(
            VoiceLocalTextCleaner.clean("五月一号要 review 一二线城市的 test。"),
            "五月一号要 review 一二线城市的 test。"
        )
    }

    func testRemovesEnglishFillersAtPhraseBoundaries() {
        XCTAssertEqual(
            VoiceLocalTextCleaner.clean("um, test one two, uh, 帮我看一下。"),
            "test one two, 帮我看一下。"
        )
    }

    func testRemovesChineseFillersAttachedToPhraseEdges() {
        XCTAssertEqual(
            VoiceLocalTextCleaner.clean("test1234，test，帮我修改一下这个。test嗯，ok。"),
            "test1234，test，帮我修改一下这个。test，ok。"
        )
    }
}
