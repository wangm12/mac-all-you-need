@testable import MacAllYouNeed
import Core
import XCTest

final class DownloadCollectionPresentationTests: XCTestCase {
    func testStatusMapsCompletedCollectionToDone() {
        var completed = makeRecord(url: "https://a", state: .completed)
        completed.collectionID = "c1"
        let group = DownloadCollectionGrouping.Group(
            id: "c1",
            title: "s09g - Videos",
            kind: .playlist,
            records: [completed],
            latestCreated: completed.created,
            completedCount: 1
        )

        let status = DownloadCollectionPresentation.status(
            for: group,
            hasActive: false,
            progress: 1
        )
        XCTAssertEqual(status, .done)
        XCTAssertEqual(status.label, "Done")
    }

    func testStatusMapsActiveCollectionToDownloading() {
        var running = makeRecord(url: "https://a", state: .running)
        running.collectionID = "c1"
        let group = DownloadCollectionGrouping.Group(
            id: "c1",
            title: "s10g - Videos",
            kind: .playlist,
            records: [running],
            latestCreated: running.created,
            completedCount: 0
        )

        XCTAssertEqual(
            DownloadCollectionPresentation.status(for: group, hasActive: true, progress: 0.2),
            .downloading
        )
    }

    func testDeleteSheetItemLabelPluralizesVideosAndPosts() {
        XCTAssertEqual(
            DownloadCollectionPresentation.deleteSheetItemLabel(count: 1, kind: .playlist),
            "1 video"
        )
        XCTAssertEqual(
            DownloadCollectionPresentation.deleteSheetItemLabel(count: 12, kind: .playlist),
            "12 videos"
        )
        XCTAssertEqual(
            DownloadCollectionPresentation.deleteSheetItemLabel(count: 2, kind: .douyinProfile),
            "2 posts"
        )
    }

    func testLocationLabelUsesDownloadsPrefixForCollectionSubfolder() {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        var record = makeRecord(
            url: "https://a",
            state: .completed,
            destinationPath: downloads.appendingPathComponent("MacAllYouNeed/s09g - Videos/video.mp4").path
        )
        record.collectionID = "c1"
        record.collectionTitle = "s09g - Videos"

        let group = DownloadCollectionGrouping.Group(
            id: "c1",
            title: "s09g - Videos",
            kind: .playlist,
            records: [record],
            latestCreated: record.created,
            completedCount: 1
        )

        let label = DownloadCollectionPresentation.locationLabel(for: group, downloadDir: "")
        XCTAssertTrue(label.contains("Downloads /"))
        XCTAssertTrue(label.contains("s09g - Videos"))
    }

    func testExpandedSubtitleIncludesSaveLocation() {
        let group = DownloadCollectionGrouping.Group(
            id: "c1",
            title: "s09g - Videos",
            kind: .playlist,
            records: [],
            latestCreated: .distantPast,
            completedCount: 0
        )
        let subtitle = DownloadCollectionPresentation.expandedSubtitle(
            for: group,
            location: "Downloads / s09g - Videos"
        )
        XCTAssertTrue(subtitle.contains("Playlist"))
        XCTAssertTrue(subtitle.contains("Saved to Downloads / s09g - Videos"))
    }

    func testProgressFillWidthIsZeroAtZeroPercent() {
        XCTAssertEqual(
            DownloadCollectionPresentation.progressFillWidth(totalWidth: 200, progress: 0),
            0
        )
    }

    func testPrimaryActionTitlePrefersRetryForFailedCollection() {
        XCTAssertEqual(
            DownloadCollectionPresentation.primaryActionTitle(
                status: .failed,
                showsPauseAll: false,
                showsResumeAll: true
            ),
            "Retry"
        )
    }

    private func makeRecord(
        url: String,
        state: DownloadState,
        destinationPath: String = "/tmp/%(title)s.%(ext)s"
    ) -> DownloadRecord {
        DownloadRecord(url: url, title: "Title", destinationPath: destinationPath, state: state)
    }
}
