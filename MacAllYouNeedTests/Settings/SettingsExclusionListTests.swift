@testable import MacAllYouNeed
import XCTest

final class SettingsExclusionListTests: XCTestCase {
    func testNormalizedBundleIDsTrimDedupeAndSort() {
        let normalized = SettingsExclusionList.normalizedBundleIDs([
            "  com.apple.Notes  ",
            "com.apple.TextEdit",
            "",
            "com.apple.Notes"
        ])

        XCTAssertEqual(normalized, ["com.apple.Notes", "com.apple.TextEdit"])
    }

    func testNormalizedRegexPatternsTrimDedupePreserveFirstSeenOrder() {
        let normalized = SettingsExclusionList.normalizedRegexPatterns([
            "  \\d{16}  ",
            "[A-Z]+",
            "\\d{16}",
            ""
        ])

        XCTAssertEqual(normalized, ["\\d{16}", "[A-Z]+"])
    }
}
