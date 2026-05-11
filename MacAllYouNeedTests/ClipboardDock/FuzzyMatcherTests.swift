@testable import MacAllYouNeed
import XCTest

final class FuzzyMatcherTests: XCTestCase {
    func testRanksExactSubstringFirst() {
        let candidates = ["alpha beta", "gamma alpha", "alpha"]
        let ranked = FuzzyMatcher.rank(candidates: candidates, query: "alpha")
        XCTAssertEqual(ranked.first, "alpha")
    }

    func testEmptyQueryReturnsAll() {
        let candidates = ["a", "b"]
        XCTAssertEqual(FuzzyMatcher.rank(candidates: candidates, query: ""), candidates)
    }

    func testNoMatchReturnsEmpty() {
        XCTAssertTrue(FuzzyMatcher.rank(candidates: ["foo"], query: "xyz").isEmpty)
    }

    func testTypoIsToleratedViaEditDistance() {
        let ranked = FuzzyMatcher.rank(candidates: ["Alpha", "Beta"], query: "alfa")
        XCTAssertEqual(ranked.first, "Alpha")
    }

    func testHandlesDuplicatePreviewsWithoutCrashing() {
        let ranked = FuzzyMatcher.rank(candidates: ["dup", "dup", "other"], query: "dup")
        XCTAssertEqual(Array(ranked.prefix(2)), ["dup", "dup"])
    }
}
