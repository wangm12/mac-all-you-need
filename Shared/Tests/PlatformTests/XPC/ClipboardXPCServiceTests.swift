@testable import Platform
import AppKit
import Core
import CryptoKit
import XCTest

final class ClipboardXPCServiceTests: XCTestCase {
    var dir: URL!
    var clip: ClipboardStore!
    var blobs: BlobStore!
    var search: SearchStore!
    var snippets: SnippetStore!
    var pasteboard: NSPasteboard!
    var service: ClipboardXPCService!

    override func setUp() {
        super.setUp()
        AppGroupSettings.defaults.removeObject(forKey: "history.sortMode")
        AppGroupSettings.defaults.removeObject(forKey: "autoPaste.behavior")
        AppGroupSettings.defaults.removeObject(forKey: "autoPaste.delayMs")
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("XPCSvc-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let key = SymmetricKey(size: .bits256)
        let device = DeviceID.generate()
        let clipDB = try! Database(
            url: dir.appendingPathComponent("c.sqlite"),
            migrations: ClipboardStore.migrations
        )
        clip = try! ClipboardStore(database: clipDB, deviceKey: key, deviceID: device)
        blobs = BlobStore(rootURL: dir.appendingPathComponent("blobs"), key: key)
        let searchDB = try! Database(
            url: dir.appendingPathComponent("s.sqlite"),
            migrations: SearchStore.migrations
        )
        search = SearchStore(database: searchDB)
        let snippetDB = try! Database(
            url: dir.appendingPathComponent("snip.sqlite"),
            migrations: SnippetStore.migrations
        )
        snippets = SnippetStore(database: snippetDB, deviceKey: key)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("test-\(UUID().uuidString)"))
        service = ClipboardXPCService(
            clip: clip, blobs: blobs, search: search, snippets: snippets, pasteboard: pasteboard
        )
    }

    override func tearDown() {
        AppGroupSettings.defaults.removeObject(forKey: "history.sortMode")
        AppGroupSettings.defaults.removeObject(forKey: "autoPaste.behavior")
        AppGroupSettings.defaults.removeObject(forKey: "autoPaste.delayMs")
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testListItemsReturnsEmptyWhenStoreEmpty() {
        let exp = expectation(description: "list")
        service.listItems(query: nil, pageToken: nil, limit: 10) { list in
            XCTAssertEqual(list.items.count, 0)
            XCTAssertNil(list.nextPageToken)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testListItemsReturnsAppendedRecord() throws {
        _ = try clip.append(.text("hello"))
        let exp = expectation(description: "list")
        service.listItems(query: nil, pageToken: nil, limit: 10) { list in
            XCTAssertEqual(list.items.count, 1)
            XCTAssertEqual(list.items.first?.preview, "hello")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testListItemsUsesFrequencySortWhenConfigured() throws {
        let first = try clip.append(.text("first"))
        let second = try clip.append(.text("second"))
        try clip.bumpFrequency(id: first.id)
        try clip.bumpFrequency(id: first.id)
        try clip.bumpFrequency(id: second.id)
        AppGroupSettings.defaults.set("frequency", forKey: "history.sortMode")

        let exp = expectation(description: "list")
        service.listItems(query: nil, pageToken: nil, limit: 10) { list in
            XCTAssertEqual(list.items.first?.id, first.id.rawValue)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testListItemsUsesRecentlyUsedSortWhenConfigured() throws {
        let first = try clip.append(.text("first"))
        let second = try clip.append(.text("second"))
        try clip.bumpFrequency(id: first.id)
        Thread.sleep(forTimeInterval: 0.005)
        try clip.bumpFrequency(id: second.id)
        AppGroupSettings.defaults.set("recentlyUsed", forKey: "history.sortMode")

        let exp = expectation(description: "list")
        service.listItems(query: nil, pageToken: nil, limit: 10) { list in
            XCTAssertEqual(list.items.first?.id, second.id.rawValue)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testListItemsCarriesSourceAppBundleID() throws {
        _ = try clip.append(.text("hi"), sourceAppBundleID: "com.apple.Terminal")
        let exp = expectation(description: "list")
        service.listItems(query: nil, pageToken: nil, limit: 10) { list in
            XCTAssertEqual(list.items.first?.sourceAppBundleID, "com.apple.Terminal")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testListItemsCarriesImageDimensionsAndBlobID() throws {
        let pixels = Data(repeating: 0xAB, count: 32)
        let blobID = try blobs.write(pixels)
        _ = try clip.append(.image(blobID: blobID, width: 800, height: 600))
        let exp = expectation(description: "list")
        service.listItems(query: nil, pageToken: nil, limit: 10) { list in
            let meta = list.items.first
            XCTAssertEqual(meta?.imageWidth, 800)
            XCTAssertEqual(meta?.imageHeight, 600)
            XCTAssertEqual(meta?.imageBlobID, blobID)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testListItemsLeavesImageFieldsZeroForTextRecords() throws {
        _ = try clip.append(.text("plain"))
        let exp = expectation(description: "list")
        service.listItems(query: nil, pageToken: nil, limit: 10) { list in
            let meta = list.items.first
            XCTAssertEqual(meta?.imageWidth, 0)
            XCTAssertEqual(meta?.imageHeight, 0)
            XCTAssertNil(meta?.imageBlobID)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testImageThumbnailReturnsJPEGForImageRecord() throws {
        let img = NSImage(size: NSSize(width: 200, height: 100))
        img.lockFocus()
        NSColor.green.setFill()
        NSRect(x: 0, y: 0, width: 200, height: 100).fill()
        img.unlockFocus()
        let tiff = img.tiffRepresentation!
        let rep = NSBitmapImageRep(data: tiff)!
        let png = rep.representation(using: .png, properties: [:])!

        let blobID = try blobs.write(png)
        let meta = try clip.append(.image(blobID: blobID, width: 200, height: 100))

        let exp = expectation(description: "thumb")
        service.imageThumbnail(forID: meta.id.rawValue, maxDim: 50) { data in
            XCTAssertNotNil(data)
            XCTAssertEqual(data?.prefix(2), Data([0xFF, 0xD8]))
            let thumb = NSImage(data: data!)!
            XCTAssertEqual(Int(thumb.size.width), 50)
            XCTAssertEqual(Int(thumb.size.height), 25)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testImageThumbnailReturnsNilForNonImageRecord() throws {
        let meta = try clip.append(.text("not an image"))
        let exp = expectation(description: "thumb")
        service.imageThumbnail(forID: meta.id.rawValue, maxDim: 50) { data in
            XCTAssertNil(data)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testImageThumbnailCachesByBlobIDAndMaxDim() throws {
        let img = NSImage(size: NSSize(width: 32, height: 32))
        img.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 32, height: 32).fill()
        img.unlockFocus()
        let png = NSBitmapImageRep(data: img.tiffRepresentation!)!
            .representation(using: .png, properties: [:])!
        let blobID = try blobs.write(png)
        let meta = try clip.append(.image(blobID: blobID, width: 32, height: 32))

        let first = expectation(description: "first")
        var firstBytes: Data?
        service.imageThumbnail(forID: meta.id.rawValue, maxDim: 16) { data in
            firstBytes = data
            first.fulfill()
        }
        wait(for: [first], timeout: 1)

        try blobs.delete(id: blobID)

        let second = expectation(description: "second")
        service.imageThumbnail(forID: meta.id.rawValue, maxDim: 16) { data in
            XCTAssertEqual(data, firstBytes)
            second.fulfill()
        }
        wait(for: [second], timeout: 1)
    }

    func testPasteManyJoinsTextWithDelimiterAndWritesPasteboard() throws {
        let a = try clip.append(.text("alpha"))
        let b = try clip.append(.text("beta"))
        let c = try clip.append(.text("gamma"))

        let exp = expectation(description: "pasteMany")
        service.pasteMany(
            itemIDs: [a.id.rawValue, b.id.rawValue, c.id.rawValue],
            delimiter: " | ",
            plainText: true
        ) { _ in exp.fulfill() }
        wait(for: [exp], timeout: 1)

        let mainExp = expectation(description: "main")
        DispatchQueue.main.async { mainExp.fulfill() }
        wait(for: [mainExp], timeout: 1)

        XCTAssertEqual(pasteboard.string(forType: .string), "alpha | beta | gamma")
    }

    func testPasteBumpsFrequency() throws {
        let item = try clip.append(.text("hello"))
        let exp = expectation(description: "paste")
        service.paste(itemID: item.id.rawValue, plainText: true) { _ in
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)

        let mainExp = expectation(description: "main")
        DispatchQueue.main.async { mainExp.fulfill() }
        wait(for: [mainExp], timeout: 1)

        let meta = try XCTUnwrap(try clip.list(limit: 10).first(where: { $0.id == item.id }))
        XCTAssertEqual(meta.frequency, 1)
        XCTAssertNotNil(meta.lastAccessed)
    }

    func testPasteManySkipsImageKindsAndPreservesOrder() throws {
        let a = try clip.append(.text("first"))
        let blobID = try blobs.write(Data([0]))
        let img = try clip.append(.image(blobID: blobID, width: 1, height: 1))
        let c = try clip.append(.text("third"))

        let exp = expectation(description: "pasteMany")
        service.pasteMany(
            itemIDs: [a.id.rawValue, img.id.rawValue, c.id.rawValue],
            delimiter: "\n",
            plainText: true
        ) { _ in exp.fulfill() }
        wait(for: [exp], timeout: 1)

        let mainExp = expectation(description: "main")
        DispatchQueue.main.async { mainExp.fulfill() }
        wait(for: [mainExp], timeout: 1)

        XCTAssertEqual(pasteboard.string(forType: .string), "first\nthird")
    }

    func testPasteTextWritesPasteboardWithoutSavingByDefault() throws {
        let exp = expectation(description: "pasteText")
        service.pasteText(text: "hello world", plainText: true, saveAsNew: false) { _ in
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
        let mainExp = expectation(description: "main")
        DispatchQueue.main.async { mainExp.fulfill() }
        wait(for: [mainExp], timeout: 1)

        XCTAssertEqual(pasteboard.string(forType: .string), "hello world")
        XCTAssertEqual(try clip.list(limit: 10).count, 0)
    }

    func testPasteTextWithSaveAsNewAppendsHistoryRecord() throws {
        let exp = expectation(description: "pasteText")
        service.pasteText(text: "saved snippet", plainText: true, saveAsNew: true) { _ in
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
        let mainExp = expectation(description: "main")
        DispatchQueue.main.async { mainExp.fulfill() }
        wait(for: [mainExp], timeout: 1)

        let items = try clip.list(limit: 10)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.preview, "saved snippet")
        XCTAssertEqual(items.first?.sourceAppBundleID, "com.macallyouneed.app")
    }

    func testTransformAndCopyAppliesTransformAndPastes() throws {
        let item = try clip.append(.text("Hello WORLD"))
        let exp = expectation(description: "transform")
        var reply: String?
        service.transformAndCopy(
            itemID: item.id.rawValue,
            transform: "lowercase",
            saveAsNew: false
        ) {
            reply = $0
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
        let mainExp = expectation(description: "main")
        DispatchQueue.main.async { mainExp.fulfill() }
        wait(for: [mainExp], timeout: 1)

        XCTAssertEqual(reply, "hello world")
        XCTAssertEqual(pasteboard.string(forType: .string), "hello world")
    }

    func testTransformAndCopyReturnsNilForUnknownTransform() throws {
        let item = try clip.append(.text("hi"))
        let exp = expectation(description: "transform")
        service.transformAndCopy(
            itemID: item.id.rawValue,
            transform: "doesNotExist",
            saveAsNew: false
        ) {
            XCTAssertNil($0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testTransformAndCopyReturnsNilForNonTextItem() throws {
        let blobID = try blobs.write(Data([0]))
        let item = try clip.append(.image(blobID: blobID, width: 1, height: 1))
        let exp = expectation(description: "transform")
        service.transformAndCopy(
            itemID: item.id.rawValue,
            transform: "lowercase",
            saveAsNew: false
        ) {
            XCTAssertNil($0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testTransformAndCopySaveAsNewAppendsHistoryRecord() throws {
        let item = try clip.append(.text("Hello"))
        let exp = expectation(description: "transform")
        service.transformAndCopy(
            itemID: item.id.rawValue,
            transform: "uppercase",
            saveAsNew: true
        ) { _ in
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
        let mainExp = expectation(description: "main")
        DispatchQueue.main.async { mainExp.fulfill() }
        wait(for: [mainExp], timeout: 1)

        let items = try clip.list(limit: 10)
        XCTAssertEqual(items.count, 2)
        let transformed = items.first { $0.preview == "HELLO" }
        XCTAssertNotNil(transformed)
        XCTAssertEqual(transformed?.sourceAppBundleID, "com.macallyouneed.app")
    }

    func testBodyFileURLsReturnsURLsForFilesRecord() throws {
        let urls = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.txt")]
        let item = try clip.append(.files(urls))
        let exp = expectation(description: "files")
        service.bodyFileURLs(forID: item.id.rawValue) { result in
            XCTAssertEqual(result, urls.map(\.path))
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testBodyFileURLsReturnsNilForNonFilesRecord() throws {
        let item = try clip.append(.text("not files"))
        let exp = expectation(description: "files")
        service.bodyFileURLs(forID: item.id.rawValue) { result in
            XCTAssertNil(result)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testMetasByIDsReturnsRequestedItemsRegardlessOfRecency() throws {
        var metas: [ClipboardItemMeta] = []
        for i in 0..<5 {
            metas.append(try clip.append(.text("v\(i)")))
            Thread.sleep(forTimeInterval: 0.002)
        }
        let oldestTwo = [metas[0].id.rawValue, metas[1].id.rawValue]
        let exp = expectation(description: "metas")
        service.metasByIDs(ids: oldestTwo) { list in
            XCTAssertEqual(list.items.count, 2)
            XCTAssertEqual(Set(list.items.map(\.id)), Set(oldestTwo))
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testMetasByIDsSkipsUnknownIDs() {
        let exp = expectation(description: "metas")
        service.metasByIDs(ids: ["01HFAKEFAKEFAKEFAKEFAKEFAK"]) { list in
            XCTAssertEqual(list.items.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testDeleteItemRemovesRecord() throws {
        let item = try clip.append(.text("doomed"))
        try search.upsert(kind: .clipboardItem, id: item.id, text: "doomed")
        let exp = expectation(description: "delete")
        service.deleteItem(id: item.id.rawValue) { ok in
            XCTAssertTrue(ok)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
        XCTAssertEqual(try clip.list(limit: 10).count, 0)
        XCTAssertEqual(
            try search.search(query: "doomed", limit: 10).count,
            0,
            "search index row must also be removed"
        )
    }

    func testDeleteItemAlsoDeletesBlobForImageRecord() throws {
        let blobID = try blobs.write(Data(repeating: 1, count: 100))
        let item = try clip.append(.image(blobID: blobID, width: 8, height: 8))
        let exp = expectation(description: "delete")
        service.deleteItem(id: item.id.rawValue) { ok in
            XCTAssertTrue(ok)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: blobs.encryptedURL(id: blobID).path),
            "blob file must be deleted along with image record"
        )
    }

    func testDeleteItemReturnsFalseForUnknownID() {
        let exp = expectation(description: "delete")
        service.deleteItem(id: "01HFAKEFAKEFAKEFAKEFAKEFAK") { ok in
            XCTAssertFalse(ok)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }
}
