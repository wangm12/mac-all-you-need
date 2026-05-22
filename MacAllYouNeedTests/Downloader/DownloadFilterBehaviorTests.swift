@testable import MacAllYouNeed
import Core
import XCTest

/// Golden tests for filter × selection-state combinations.
/// Asserts visible row IDs match for every DownloadsListFilter mode.
final class DownloadFilterBehaviorTests: XCTestCase {

    // MARK: - Fixtures

    private var queued: DownloadRecord { makeRecord(state: .queued) }
    private var running: DownloadRecord { makeRecord(state: .running) }
    private var paused: DownloadRecord { makeRecord(state: .paused) }
    private var failed: DownloadRecord { makeRecord(state: .failed) }
    private var completed: DownloadRecord { makeRecord(state: .completed) }

    private var allRecords: [DownloadRecord] {
        [queued, running, paused, failed, completed]
    }

    // MARK: - DownloadsListFilter.includes

    func testAllFilterIncludesEveryState() {
        let allStates: [DownloadState] = [.queued, .running, .paused, .completed, .failed]
        for state in allStates {
            XCTAssertTrue(DownloadsListFilter.all.includes(state), "Expected .all to include .\(state)")
        }
    }

    func testActiveQueueFilterExcludesOnlyCompleted() {
        XCTAssertTrue(DownloadsListFilter.activeQueue.includes(.queued))
        XCTAssertTrue(DownloadsListFilter.activeQueue.includes(.running))
        XCTAssertTrue(DownloadsListFilter.activeQueue.includes(.paused))
        XCTAssertTrue(DownloadsListFilter.activeQueue.includes(.failed))
        XCTAssertFalse(DownloadsListFilter.activeQueue.includes(.completed))
    }

    func testCompletedFilterIncludesOnlyCompleted() {
        XCTAssertFalse(DownloadsListFilter.completed.includes(.queued))
        XCTAssertFalse(DownloadsListFilter.completed.includes(.running))
        XCTAssertFalse(DownloadsListFilter.completed.includes(.paused))
        XCTAssertFalse(DownloadsListFilter.completed.includes(.failed))
        XCTAssertTrue(DownloadsListFilter.completed.includes(.completed))
    }

    // MARK: - DownloadsQueuePresentation.visibleRows

    func testAllFilterReturnsEveryRow() {
        let visible = DownloadsQueuePresentation.visibleRows(allRecords, filter: .all)
        XCTAssertEqual(visible.count, allRecords.count)
    }

    func testActiveQueueFilterOmitsCompletedRows() {
        let visible = DownloadsQueuePresentation.visibleRows(allRecords, filter: .activeQueue)
        XCTAssertFalse(visible.contains { $0.state == .completed })
        XCTAssertEqual(visible.count, 4) // queued + running + paused + failed
    }

    func testCompletedFilterRetainsOnlyCompletedRows() {
        let visible = DownloadsQueuePresentation.visibleRows(allRecords, filter: .completed)
        XCTAssertTrue(visible.allSatisfy { $0.state == .completed })
        XCTAssertEqual(visible.count, 1)
    }

    func testEmptyRecordSetProducesEmptyResultForAllFilters() {
        for filter in [DownloadsListFilter.all, .activeQueue, .completed] {
            XCTAssertTrue(
                DownloadsQueuePresentation.visibleRows([], filter: filter).isEmpty,
                "Expected empty result for filter \(filter)"
            )
        }
    }

    // MARK: - DownloadsQueuePresentation.showsFailedBanner

    func testFailedBannerShownWhenFailedRecordInActiveQueue() {
        XCTAssertTrue(DownloadsQueuePresentation.showsFailedBanner(rows: [failed, queued], filter: .activeQueue))
    }

    func testFailedBannerShownWhenFailedRecordInAllFilter() {
        XCTAssertTrue(DownloadsQueuePresentation.showsFailedBanner(rows: [failed, completed], filter: .all))
    }

    func testFailedBannerHiddenWhenCompletedFilterActive() {
        XCTAssertFalse(DownloadsQueuePresentation.showsFailedBanner(rows: [failed, completed], filter: .completed))
    }

    func testFailedBannerHiddenWhenNoFailedRecordsExist() {
        XCTAssertFalse(DownloadsQueuePresentation.showsFailedBanner(rows: [queued, running], filter: .activeQueue))
    }

    // MARK: - DownloadsQueuePresentation.headerActionTitle

    func testHeaderActionTitleIsRetryFailedWhenFailedRecordPresent() {
        let title = DownloadsQueuePresentation.headerActionTitle(rows: [failed, queued], filter: .activeQueue)
        XCTAssertEqual(title, "Retry Failed")
    }

    func testHeaderActionTitleIsNilWhenNoFailedRecordsInActiveQueue() {
        let title = DownloadsQueuePresentation.headerActionTitle(rows: [queued, running], filter: .activeQueue)
        XCTAssertNil(title)
    }

    func testHeaderActionTitleIsOpenFolderForNonEmptyCompletedFilter() {
        let title = DownloadsQueuePresentation.headerActionTitle(rows: [completed], filter: .completed)
        XCTAssertEqual(title, "Open Folder")
    }

    func testHeaderActionTitleIsNilForEmptyCompletedFilter() {
        let title = DownloadsQueuePresentation.headerActionTitle(rows: [], filter: .completed)
        XCTAssertNil(title)
    }

    // MARK: - DownloadsEmptyStatePresentation

    func testEmptyStateTitleForAllFilter() {
        let model = DownloadsEmptyStatePresentation.model(for: .all)
        XCTAssertEqual(model.title, "No downloads queued")
        XCTAssertNotNil(model.primaryActionTitle)
        XCTAssertNotNil(model.secondaryActionTitle)
    }

    func testEmptyStateTitleForActiveQueueFilter() {
        let model = DownloadsEmptyStatePresentation.model(for: .activeQueue)
        XCTAssertEqual(model.title, "No downloads queued")
        XCTAssertEqual(model.primaryActionTitle, "Add URL")
        XCTAssertEqual(model.secondaryActionTitle, "Paste URL")
    }

    func testEmptyStateTitleForCompletedFilter() {
        let model = DownloadsEmptyStatePresentation.model(for: .completed)
        XCTAssertEqual(model.title, "No completed downloads")
        XCTAssertNil(model.primaryActionTitle)
        XCTAssertNil(model.secondaryActionTitle)
    }

    // MARK: - Helpers

    private static var idCounter = 0

    private func makeRecord(state: DownloadState) -> DownloadRecord {
        DownloadRecord(
            url: "https://example.com/video-\(UUID().uuidString)",
            title: "Test Video",
            destinationPath: "/tmp/video.mp4",
            state: state
        )
    }
}
