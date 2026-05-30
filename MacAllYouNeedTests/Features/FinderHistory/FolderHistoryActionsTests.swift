@testable import MacAllYouNeed
import XCTest

final class FolderHistoryActionsTests: XCTestCase {
    func testURLConstruction() {
        let url = URL(fileURLWithPath: "/Users/me/Documents")
        XCTAssertTrue(url.isFileURL)
        XCTAssertEqual(url.path, "/Users/me/Documents")
    }
}
