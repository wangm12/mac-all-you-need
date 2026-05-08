@testable import Core
import XCTest

final class ClipboardXPCInteractingTests: XCTestCase {
    final class MockClient: ClipboardXPCInteracting, @unchecked Sendable {
        var listed = false

        func listItems(query: String?, pageToken: String?, limit: Int) async -> ClipboardXPCList {
            listed = true
            return ClipboardXPCList(items: [], nextPageToken: nil)
        }

        func metasByIDs(ids: [String]) async -> ClipboardXPCList {
            ClipboardXPCList(items: [], nextPageToken: nil)
        }

        func bodyText(forID id: String) async -> String? { nil }
        func bodyFileURLs(forID id: String) async -> [String]? { nil }
        func paste(itemID: String, plainText: Bool) async -> String { "injected" }
        func pasteMany(itemIDs: [String], delimiter: String, plainText: Bool) async -> String { "injected" }
        func pasteText(text: String, plainText: Bool, saveAsNew: Bool) async -> String { "injected" }
        func transformAndCopy(itemID: String, transform: String, saveAsNew: Bool) async -> String? { nil }
        func imageThumbnail(forID id: String, maxDim: Int) async -> Data? { nil }
        func listSnippets() async -> [SnippetXPCDTO] { [] }
    }

    func testMockSatisfiesProtocol() async {
        let mock = MockClient()
        let list = await mock.listItems(query: nil, pageToken: nil, limit: 10)
        XCTAssertEqual(list.items.count, 0)
        XCTAssertTrue(mock.listed)
    }
}
