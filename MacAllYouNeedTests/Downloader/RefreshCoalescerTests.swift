@testable import MacAllYouNeed
import Core
import XCTest

final class RefreshCoalescerTests: XCTestCase {
    func testBulkRefreshWinsOverRegularRefresh() {
        var coalescer = DownloaderViewModel.RefreshCoalescer()

        coalescer.schedule(kind: .regular)
        coalescer.schedule(kind: .bulk)

        let scheduled = coalescer.startIfNeeded()
        XCTAssertEqual(scheduled?.kind, .bulk)
        XCTAssertEqual(scheduled?.delay, 750_000_000)
    }

    func testPendingRefreshIsPreservedWhileInFlight() {
        var coalescer = DownloaderViewModel.RefreshCoalescer()

        let first = coalescer.startIfNeeded()
        XCTAssertEqual(first?.kind, .regular)
        XCTAssertEqual(first?.delay, 300_000_000)

        coalescer.schedule(kind: .bulk)
        let second = coalescer.startIfNeeded()
        XCTAssertNil(second)

        let finished = coalescer.finish()
        XCTAssertTrue(finished.shouldReschedule)
        XCTAssertEqual(finished.kind, .bulk)
    }

    func testNeedsFullRefreshDependsOnCountAndLatestModified() {
        let previous = DownloadStore.SnapshotSummary(count: 200, modifiedMax: 100)
        let sameCountDifferentModified = DownloadStore.SnapshotSummary(count: 200, modifiedMax: 999)
        let differentCount = DownloadStore.SnapshotSummary(count: 201, modifiedMax: 999)

        XCTAssertTrue(DownloaderViewModel.needsFullRefresh(
            newSummary: sameCountDifferentModified,
            previousSummary: previous
        ))
        XCTAssertTrue(DownloaderViewModel.needsFullRefresh(
            newSummary: differentCount,
            previousSummary: previous
        ))
    }

    func testLargePresentationDisablesThumbnails() {
        let rows = (0..<101).map { index in
            DownloadRecord(
                url: "https://example.com/\(index)",
                title: "Video \(index)",
                destinationPath: "/tmp/video-\(index).mp4",
                state: .queued
            )
        }
        let presentation = DownloadsListPresentation(rows: rows, liveProgress: [:])

        XCTAssertFalse(presentation.shouldShowThumbnails(for: .all))
        XCTAssertFalse(presentation.shouldShowThumbnails(for: .activeQueue))
        XCTAssertFalse(presentation.shouldShowThumbnails(for: .completed))
    }

    func testPresentationKeepsLargeListsQueryableWithoutThrowing() {
        let rows = (0..<200).map { index in
            DownloadRecord(
                url: "https://example.com/\(index)",
                title: "Video \(index)",
                destinationPath: "/tmp/video-\(index).mp4",
                state: index % 3 == 0 ? .running : .queued
            )
        }
        let presentation = DownloadsListPresentation(rows: rows, liveProgress: [:])

        XCTAssertEqual(presentation.visibleRows(for: .all).count, 200)
        XCTAssertEqual(presentation.listItems(for: .all).count, 200)
        XCTAssertTrue(presentation.bulkActions(for: .all).contains(.pauseAll))
        XCTAssertFalse(presentation.shouldShowThumbnails(for: .all))
    }
}
