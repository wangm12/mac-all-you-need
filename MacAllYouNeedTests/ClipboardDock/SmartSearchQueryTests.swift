@testable import MacAllYouNeed
import XCTest

final class SmartSearchQueryTests: XCTestCase {
    func testFreeTextOnly() {
        let q = SmartSearchQuery("hello world")
        XCTAssertEqual(q.freeText, "hello world")
        XCTAssertFalse(q.hasOperators)
    }

    func testAppFilter() {
        let q = SmartSearchQuery("/app:Safari notes")
        XCTAssertEqual(q.appFilters, ["safari"])
        XCTAssertEqual(q.freeText, "notes")
        XCTAssertTrue(q.hasOperators)
    }

    func testNegatedAppFilter() {
        let q = SmartSearchQuery("-/app:Slack")
        XCTAssertEqual(q.negatedApps, ["slack"])
        XCTAssertTrue(q.appFilters.isEmpty)
    }

    func testTypeFiltersAreOR() {
        let q = SmartSearchQuery("/type:url /type:email")
        XCTAssertEqual(q.typeFilters, ["url", "email"])
    }

    func testDateToday() {
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let q = SmartSearchQuery("/date:today", now: now, calendar: cal)
        XCTAssertEqual(q.dateOnOrAfter, cal.startOfDay(for: now))
    }

    func testDateRelativeDays() {
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let q = SmartSearchQuery("/date:7d", now: now, calendar: cal)
        let expected = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: now))
        XCTAssertEqual(q.dateOnOrAfter, expected)
    }

    func testDateYearMonth() {
        let cal = Calendar(identifier: .gregorian)
        let q = SmartSearchQuery("/date:2026-01", calendar: cal)
        XCTAssertNotNil(q.dateOnOrAfter)
    }

    func testSlashInWordIsFreeText() {
        let q = SmartSearchQuery("a/b path")
        XCTAssertEqual(q.freeText, "a/b path")
        XCTAssertFalse(q.hasOperators)
    }

    func testCombinedOperators() {
        let q = SmartSearchQuery("/app:Safari /type:url query")
        XCTAssertEqual(q.appFilters, ["safari"])
        XCTAssertEqual(q.typeFilters, ["url"])
        XCTAssertEqual(q.freeText, "query")
    }
}
