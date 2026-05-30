import XCTest
@testable import Core

final class FolderHistorySkipRulesTests: XCTestCase {
    func testSkipsRoot() {
        XCTAssertTrue(FolderHistorySkipRules.shouldSkip(path: "/", exclusions: []))
    }

    func testSkipsTmp() {
        XCTAssertTrue(FolderHistorySkipRules.shouldSkip(path: "/tmp", exclusions: []))
        XCTAssertTrue(FolderHistorySkipRules.shouldSkip(path: "/private/var", exclusions: []))
    }

    func testSkipsLibrarySubdirectory() {
        let path = NSHomeDirectory() + "/Library/Application Support"
        XCTAssertTrue(FolderHistorySkipRules.shouldSkip(path: path, exclusions: []))
    }

    func testSkipsHiddenDirectory() {
        XCTAssertTrue(FolderHistorySkipRules.shouldSkip(path: "/Users/me/.config", exclusions: []))
    }

    func testSkipsExplicitExclusion() {
        XCTAssertTrue(FolderHistorySkipRules.shouldSkip(path: "/Users/me/Secret", exclusions: ["/Users/me/Secret"]))
    }

    func testAllowsNormalFolder() {
        XCTAssertFalse(FolderHistorySkipRules.shouldSkip(path: "/Users/me/Documents", exclusions: []))
    }
}
