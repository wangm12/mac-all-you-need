@testable import MacAllYouNeed
import Core
import XCTest

final class DownloadCollectionGroupingTests: XCTestCase {
    func testGroupsRecordsByCollectionID() {
        let collectionID = "batch-1"
        var first = DownloadRecord(url: "https://a", title: "A", destinationPath: "/a", state: .queued)
        first.collectionID = collectionID
        first.collectionIndex = 1
        first.collectionTitle = "My Playlist"
        var second = DownloadRecord(url: "https://b", title: "B", destinationPath: "/b", state: .queued)
        second.collectionID = collectionID
        second.collectionIndex = 2
        second.collectionTitle = "My Playlist"
        let single = DownloadRecord(url: "https://c", title: "C", destinationPath: "/c", state: .queued)

        let items = DownloadCollectionGrouping.items(from: [first, second, single])
        XCTAssertEqual(items.filter {
            if case .group = $0 { return true }
            return false
        }.count, 1)
        XCTAssertEqual(items.filter {
            if case .single = $0 { return true }
            return false
        }.count, 1)
    }

    func testAggregateProgressCountsCompletedRows() {
        var completed = DownloadRecord(url: "https://a", title: "A", destinationPath: "/a", state: .completed)
        completed.collectionID = "g1"
        var running = DownloadRecord(url: "https://b", title: "B", destinationPath: "/b", state: .running)
        running.collectionID = "g1"
        let progress = DownloadProgress(fraction: 0.5, speedBytesPerSec: nil, etaSeconds: nil, downloadedBytes: 50, totalBytes: 100)
        let value = DownloadCollectionGrouping.aggregateProgress(
            records: [completed, running],
            liveProgress: [running.id.rawValue: progress]
        )
        XCTAssertEqual(value, 0.75, accuracy: 0.001)
    }

    func testDouyinExtractSecUidFromProfileURLWithQuery() {
        let url = "https://www.douyin.com/user/MS4wLjABAAAAH7bR1jsG3QEo46LvfvW3J8ILrCbJN1qGKXgwRorKaGmhouCHp5e0ADIOclAJ4V-v?from_tab_name=main&vid=7648544231288699385"
        XCTAssertEqual(
            DouyinProfileLister.extractSecUid(from: url),
            "MS4wLjABAAAAH7bR1jsG3QEo46LvfvW3J8ILrCbJN1qGKXgwRorKaGmhouCHp5e0ADIOclAJ4V-v"
        )
    }

    func testDouyinParsePostsSupportsAwemeIdVariantsAndVideoURLs() {
        let html = """
        <script>
        {"aweme_id":"7648544231288699385"}
        {"aweme_id":7648544231288699386}
        {"awemeId":"7648544231288699387"}
        {"awemeId":7648544231288699388}
        <a href="/video/7648544231288699389">v</a>
        </script>
        """
        let rows = DouyinProfileLister.parsePosts(from: html, profileURL: "https://www.douyin.com/user/test")
        let ids = Set(rows.map(\.awemeId))
        XCTAssertEqual(ids.count, 5)
        XCTAssertTrue(ids.contains("7648544231288699385"))
        XCTAssertTrue(ids.contains("7648544231288699386"))
        XCTAssertTrue(ids.contains("7648544231288699387"))
        XCTAssertTrue(ids.contains("7648544231288699388"))
        XCTAssertTrue(ids.contains("7648544231288699389"))
    }

    func testDouyinParsePostsSupportsEmbeddedItemListJSON() {
        let html = """
        <html><body><script>
        window._ROUTER_DATA = {"foo":{"item_list":[{"aweme_id":"7648544231288699390","desc":"hello","author":{"nickname":"tester"}}]}};
        </script></body></html>
        """
        let rows = DouyinProfileLister.parsePosts(from: html, profileURL: "https://www.douyin.com/user/test")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.awemeId, "7648544231288699390")
        XCTAssertEqual(rows.first?.title, "hello")
        XCTAssertEqual(rows.first?.author, "tester")
    }

}
