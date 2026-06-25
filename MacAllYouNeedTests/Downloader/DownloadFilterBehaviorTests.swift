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

    func testAllFilterShowsActiveRowsBeforeCompletedRows() {
        let active = makeRecord(state: .queued)
        let finished = makeRecord(state: .completed)

        let visible = DownloadsQueuePresentation.visibleRows([finished, active], filter: .all)
        XCTAssertEqual(visible.map(\.state), [.queued, .completed])
        XCTAssertEqual(visible.first?.id, active.id)
        XCTAssertEqual(visible.last?.id, finished.id)
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

    // MARK: - DownloadsQueuePresentation.bulkActions

    func testBulkActionsIncludeRetryAndClearForFailedActiveQueue() {
        let actions = DownloadsQueuePresentation.bulkActions(rows: [failed, queued], filter: .activeQueue)
        XCTAssertTrue(actions.contains(.retryAll))
        XCTAssertTrue(actions.contains(.startAll))
        XCTAssertTrue(actions.contains(.clearAll))
    }

    func testBulkActionsIncludePauseForRunningRows() {
        let actions = DownloadsQueuePresentation.bulkActions(rows: [running, queued], filter: .activeQueue)
        XCTAssertTrue(actions.contains(.pauseAll))
        XCTAssertFalse(actions.contains(.retryAll))
    }

    func testBulkActionsForCompletedOnlyAllFilter() {
        let actions = DownloadsQueuePresentation.bulkActions(rows: [completed], filter: .all)
        XCTAssertEqual(actions, [.openFolder, .clearAll])
    }

    func testBulkActionsForCompletedFilter() {
        let actions = DownloadsQueuePresentation.bulkActions(rows: [completed], filter: .completed)
        XCTAssertEqual(actions, [.openFolder, .clearAll])
    }

    func testBulkActionsEmptyWhenNoRows() {
        XCTAssertTrue(DownloadsQueuePresentation.bulkActions(rows: [], filter: .all).isEmpty)
    }

    // MARK: - DownloadsQueuePresentation.headerActionTitle (legacy)

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

    func testCompletedBulkActionsDoNotExposeQueueActions() {
        let actions = DownloadsQueuePresentation.bulkActions(rows: [completed], filter: .completed)
        XCTAssertEqual(actions, [.openFolder, .clearAll])
        XCTAssertFalse(actions.contains(.pauseAll))
        XCTAssertFalse(actions.contains(.resumeAll))
        XCTAssertFalse(actions.contains(.retryAll))
        XCTAssertFalse(actions.contains(.startAll))
    }

    func testCompletedRecordOpenTargetUsesParentFolder() {
        let record = DownloadRecord(
            url: "https://example.com/video",
            title: "Video",
            destinationPath: "/tmp/downloads/video.mp4",
            state: .completed
        )

        let target = DownloadFolderOpenTarget.completedRecord(record)

        XCTAssertEqual(target.folderURL.path, "/tmp/downloads")
    }

    func testBulkActionsRemainStableForLargeMixedQueue() {
        let records: [DownloadRecord] = (0..<200).map { index in
            let state: DownloadState = switch index % 5 {
            case 0: .running
            case 1: .queued
            case 2: .paused
            case 3: .failed
            default: .completed
            }
            return DownloadRecord(
                url: "https://example.com/video-\(index)",
                title: "Video \(index)",
                destinationPath: "/tmp/video-\(index).mp4",
                state: state
            )
        }

        let allActions = DownloadsQueuePresentation.bulkActions(rows: records, filter: .all)
        let activeActions = DownloadsQueuePresentation.bulkActions(rows: records, filter: .activeQueue)
        let completedActions = DownloadsQueuePresentation.bulkActions(rows: records, filter: .completed)

        XCTAssertTrue(allActions.contains(.pauseAll))
        XCTAssertTrue(allActions.contains(.resumeAll))
        XCTAssertTrue(allActions.contains(.retryAll))
        XCTAssertTrue(allActions.contains(.startAll))
        XCTAssertTrue(allActions.contains(.clearAll))

        XCTAssertTrue(activeActions.contains(.pauseAll))
        XCTAssertTrue(activeActions.contains(.resumeAll))
        XCTAssertTrue(activeActions.contains(.retryAll))
        XCTAssertTrue(activeActions.contains(.startAll))
        XCTAssertTrue(activeActions.contains(.clearAll))

        XCTAssertEqual(completedActions, [.openFolder, .clearAll])
    }

    func testDownloadsListPresentationBuildsLargeBulkSnapshot() {
        let records: [DownloadRecord] = (0..<200).map { index in
            var record = DownloadRecord(
                url: "https://example.com/video-\(index)",
                title: "Video \(index)",
                destinationPath: "/tmp/video-\(index).mp4",
                state: index.isMultiple(of: 3) ? .running : .queued
            )
            if index.isMultiple(of: 4) {
                record.collectionID = "collection"
                record.collectionIndex = index + 1
                record.collectionTitle = "Playlist"
                record.collectionKind = .playlist
            }
            return record
        }
        let liveProgress = Dictionary(uniqueKeysWithValues: records.prefix(20).map { record in
            (
                record.id.rawValue,
                DownloadProgress(
                    fraction: 0.5,
                    speedBytesPerSec: 1024,
                    etaSeconds: 12,
                    downloadedBytes: 512,
                    totalBytes: 1024
                )
            )
        })

        let presentation = DownloadsListPresentation(rows: records, liveProgress: liveProgress)

        XCTAssertEqual(presentation.visibleRows(for: .all).count, 200)
        XCTAssertFalse(presentation.listItems(for: .all).isEmpty)
        XCTAssertTrue(presentation.bulkActions(for: .all).contains(.clearAll))
    }

    // MARK: - DownloadsEmptyStatePresentation

    func testEmptyStateTitleForAllFilter() {
        let model = DownloadsEmptyStatePresentation.model(for: .all)
        XCTAssertEqual(model.title, "No downloads yet")
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
