@testable import Platform
import XCTest

final class ExclusionRulesTests: XCTestCase {
    func testConcealedUTIBlocks() {
        let rules = ExclusionRules()
        XCTAssertTrue(rules.shouldExclude(types: ["org.nspasteboard.ConcealedType", "public.utf8-plain-text"], appBundleID: "com.example"))
    }

    func testAppBundleIDBlocks() {
        let rules = ExclusionRules(blockedBundleIDs: ["com.agilebits.onepassword7"])
        XCTAssertTrue(rules.shouldExclude(types: ["public.utf8-plain-text"], appBundleID: "com.agilebits.onepassword7"))
    }

    func testNonBlockedAllowed() {
        let rules = ExclusionRules()
        XCTAssertFalse(rules.shouldExclude(types: ["public.utf8-plain-text"], appBundleID: "com.example"))
    }

    func testNilBundleIDIsAllowed() {
        let rules = ExclusionRules()
        XCTAssertFalse(rules.shouldExclude(types: ["public.utf8-plain-text"], appBundleID: nil))
    }
}
