@testable import MacAllYouNeed
import AppKit
import Core
import XCTest

final class ImageBlobLoaderTests: XCTestCase {
    final class MockClient: ClipboardXPCInteracting, @unchecked Sendable {
        var thumbnailCalls = 0
        var thumbnailToReturn: Data?

        func listItems(query: String?, pageToken: String?, limit: Int) async -> ClipboardXPCList {
            ClipboardXPCList(items: [], nextPageToken: nil)
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

        func imageThumbnail(forID id: String, maxDim: Int) async -> Data? {
            thumbnailCalls += 1
            return thumbnailToReturn
        }

        func listSnippets() async -> [SnippetXPCDTO] { [] }
        func deleteItem(id: String) async -> Bool { false }
    }

    func testLoadReturnsImageOnSuccess() async {
        let mock = MockClient()
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill()
        image.unlockFocus()
        let tiff = image.tiffRepresentation!
        let rep = NSBitmapImageRep(data: tiff)!
        mock.thumbnailToReturn = rep.representation(using: .jpeg, properties: [:])
        let loader = ImageBlobLoader(xpc: mock)
        let result = await loader.thumbnail(recordID: "b1", maxDim: 32)
        XCTAssertNotNil(result)
    }

    func testLoadReturnsNilWhenXPCReturnsNil() async {
        let mock = MockClient()
        mock.thumbnailToReturn = nil
        let loader = ImageBlobLoader(xpc: mock)
        let result = await loader.thumbnail(recordID: "b1", maxDim: 32)
        XCTAssertNil(result)
    }

    func testLoadCachesByRecordIDAndMaxDim() async {
        let mock = MockClient()
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        image.unlockFocus()
        mock.thumbnailToReturn = NSBitmapImageRep(data: image.tiffRepresentation!)?
            .representation(using: .jpeg, properties: [:])
        let loader = ImageBlobLoader(xpc: mock)
        _ = await loader.thumbnail(recordID: "b1", maxDim: 32)
        _ = await loader.thumbnail(recordID: "b1", maxDim: 32)
        XCTAssertEqual(mock.thumbnailCalls, 1)
    }
}
