import Core
import XCTest

final class WindowRuleTests: XCTestCase {
    func testBundleRuleMatches() {
        let rule = WindowRule(bundleID: "com.apple.Safari", action: .ignore)
        XCTAssertTrue(rule.matches(bundleID: "com.apple.Safari", title: "Tabs"))
        XCTAssertFalse(rule.matches(bundleID: "com.apple.Mail", title: "Inbox"))
    }

    func testTitlePatternSubstring() {
        let rule = WindowRule(titlePattern: "debug", action: .ignore)
        XCTAssertTrue(rule.matches(bundleID: nil, title: "My debug window"))
    }
}
