@testable import MacAllYouNeed
import Core
import XCTest

final class DownloadsPagePresentationTests: XCTestCase {
    func testMetricsCountsAllStatusBuckets() {
        let rows = [
            makeRecord(url: "https://a", state: .completed),
            makeRecord(url: "https://b", state: .running),
            makeRecord(url: "https://c", state: .queued),
            makeRecord(url: "https://d", state: .paused),
            makeRecord(url: "https://e", state: .failed)
        ]

        let metrics = DownloadsPagePresentation.metrics(rows: rows)

        XCTAssertEqual(metrics.totalVideos, 5)
        XCTAssertEqual(metrics.completed, 1)
        XCTAssertEqual(metrics.activeCount, 2)
        XCTAssertEqual(metrics.pausedCount, 1)
        XCTAssertEqual(metrics.failedCount, 1)
    }

    func testStatusFilterIncludesOnlyMatchingRows() {
        let rows = [
            makeRecord(url: "https://a", state: .failed),
            makeRecord(url: "https://b", state: .completed)
        ]

        let filtered = DownloadsPagePresentation.filterRows(
            rows,
            statusFilter: .failed,
            query: ""
        )

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.state, .failed)
    }

    func testFilterRowsMatchesTitleChannelAndURL() {
        var record = makeRecord(url: "https://youtube.com/watch?v=abc", state: .completed)
        record.videoTitle = "Morning Routine"
        record.channelName = "Daily Vlog"

        let filtered = DownloadsPagePresentation.filterRows(
            [record],
            statusFilter: .all,
            query: "morning"
        )

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.id, record.id)
    }

    func testListItemsListModeReturnsFlatSingles() {
        var older = makeRecord(url: "https://old", state: .completed)
        var newer = makeRecord(url: "https://new", state: .completed)
        newer.modified = older.modified.addingTimeInterval(60)
        older.modified = newer.modified.addingTimeInterval(-120)

        let items = DownloadsPagePresentation.listItems(
            from: [older, newer],
            mode: .list
        )

        XCTAssertEqual(items.count, 2)
        guard case let .single(first) = items[0] else {
            return XCTFail("Expected single item")
        }
        XCTAssertEqual(first.id, newer.id)
    }

    func testSectionTitleUsesCollectionsWhenGroupedHasGroups() {
        XCTAssertEqual(
            DownloadsPagePresentation.sectionTitle(mode: .grouped, hasGroups: true),
            "Collections"
        )
        XCTAssertEqual(
            DownloadsPagePresentation.sectionTitle(mode: .list, hasGroups: true),
            "Items"
        )
    }

    func testFailedBannerTitlePluralizes() {
        XCTAssertEqual(
            DownloadsPagePresentation.failedBannerTitle(failedCount: 1),
            "1 download failed"
        )
        XCTAssertEqual(
            DownloadsPagePresentation.failedBannerTitle(failedCount: 200),
            "200 downloads failed"
        )
    }

    private func makeRecord(url: String, state: DownloadState) -> DownloadRecord {
        DownloadRecord(url: url, title: "Title", destinationPath: "/tmp/%(title)s.%(ext)s", state: state)
    }
}
