import Foundation
@testable import MacAllYouNeed
import XCTest

final class MAYNListPaginationTests: XCTestCase {
    func testMakeClampsRequestedPage() {
        let state = MAYNListPagination.make(totalItems: 100, requestedPage: 99, pageSize: 20)

        XCTAssertEqual(state.currentPage, 4)
        XCTAssertEqual(state.totalPages, 5)
    }

    func testSliceReturnsCurrentWindow() {
        let items = Array(0 ..< 30)
        let pagination = MAYNListPagination.make(totalItems: items.count, requestedPage: 1, pageSize: 10)

        XCTAssertEqual(MAYNListPagination.slice(items, pagination: pagination), Array(10 ..< 20))
    }

    func testParseJumpTextAcceptsOneBasedPageNumbers() {
        XCTAssertEqual(MAYNListPagination.parseJumpText("3", totalPages: 8), 2)
        XCTAssertEqual(MAYNListPagination.parseJumpText(" 12 ", totalPages: 8), 7)
        XCTAssertNil(MAYNListPagination.parseJumpText("0", totalPages: 8))
        XCTAssertNil(MAYNListPagination.parseJumpText("abc", totalPages: 8))
    }

    func testRangeTextUsesVisibleCount() {
        let state = MAYNListPagination.make(totalItems: 40, requestedPage: 1, pageSize: 15)

        XCTAssertEqual(state.rangeText(visibleItemCount: 15), "16-30 of 40")
    }
}
