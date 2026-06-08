import XCTest
@testable import Core

final class FolderHistoryDisplayLimitsTests: XCTestCase {
    func testQuickPickCountIsNine() {
        XCTAssertEqual(FolderHistoryDisplayLimits.quickPickCount, 9)
    }
}
