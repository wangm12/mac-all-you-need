@testable import MacAllYouNeed
import Core
import XCTest

final class FileURLLoaderTests: XCTestCase {
    final class MockClient: ClipboardXPCInteracting, @unchecked Sendable {
        var calls = 0
        var paths: [String]? = ["/tmp/a.txt", "/tmp/b.txt"]

        func listItems(query: String?, pageToken: String?, limit: Int) async -> ClipboardXPCList {
            ClipboardXPCList(items: [], nextPageToken: nil)
        }

        func metasByIDs(ids: [String]) async -> ClipboardXPCList {
            ClipboardXPCList(items: [], nextPageToken: nil)
        }

        func bodyText(forID id: String) async -> String? { nil }

        func bodyFileURLs(forID id: String) async -> [String]? {
            calls += 1
            return paths
        }

        func paste(itemID: String, plainText: Bool) async -> String { "injected" }
        func pasteMany(itemIDs: [String], delimiter: String, plainText: Bool) async -> String { "injected" }
        func pasteText(text: String, plainText: Bool, saveAsNew: Bool) async -> String { "injected" }
        func transformAndCopy(itemID: String, transform: String, saveAsNew: Bool) async -> String? { nil }
        func imageThumbnail(forID id: String, maxDim: Int) async -> Data? { nil }
        func listSnippets() async -> [SnippetXPCDTO] { [] }
    }

    func testLoadReturnsURLs() async {
        let mock = MockClient()
        let loader = FileURLLoader(xpc: mock)
        let urls = await loader.urls(recordID: "i1")
        XCTAssertEqual(urls?.map(\.path), ["/tmp/a.txt", "/tmp/b.txt"])
    }

    func testLoadCachesByRecordID() async {
        let mock = MockClient()
        let loader = FileURLLoader(xpc: mock)
        _ = await loader.urls(recordID: "i1")
        _ = await loader.urls(recordID: "i1")
        XCTAssertEqual(mock.calls, 1)
    }

    func testLoadReturnsNilOnXPCMiss() async {
        let mock = MockClient()
        mock.paths = nil
        let loader = FileURLLoader(xpc: mock)
        let urls = await loader.urls(recordID: "i1")
        XCTAssertNil(urls)
    }
}
