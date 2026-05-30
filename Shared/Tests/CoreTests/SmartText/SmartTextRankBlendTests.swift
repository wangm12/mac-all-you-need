@testable import Core
import XCTest

final class SmartTextRankBlendTests: XCTestCase {
    func testLexicalOnlyOrder() {
        let order = SmartTextRankBlend.blend(
            lexicalScores: ["a": 1.0, "b": 3.0, "c": 2.0],
            semanticScores: [:],
            weight: 0.0
        )
        XCTAssertEqual(order, ["b", "c", "a"])
    }

    func testSemanticWeightChangesOrder() {
        // Lexical alone ranks a over b; a strong semantic signal on b with
        // weight 1.0 flips them.
        let order = SmartTextRankBlend.blend(
            lexicalScores: ["a": 1.0, "b": 0.5],
            semanticScores: ["a": 0.0, "b": 1.0],
            weight: 1.0
        )
        XCTAssertEqual(order, ["b", "a"])
    }

    func testTieBreaksByKey() {
        let order = SmartTextRankBlend.blend(
            lexicalScores: ["z": 1.0, "a": 1.0],
            semanticScores: [:],
            weight: 0.0
        )
        XCTAssertEqual(order, ["a", "z"])
    }
}
