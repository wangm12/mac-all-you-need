import AppKit
import Core
import XCTest
@testable import MacAllYouNeed

final class DockPreviewThumbnailDiskStoreTests: XCTestCase {
    private var tempRoot: URL!
    private var store: DockPreviewThumbnailDiskStore!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("dock-thumb-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        store = DockPreviewThumbnailDiskStore(rootURL: tempRoot)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    func testWriteIsFreshAndLoad() async throws {
        let image = makeTestCGImage()
        let capturedAt = Date(timeIntervalSince1970: 3_000)
        await store.write(pid: 42, windowID: 7, cgImage: image, capturedAt: capturedAt)

        XCTAssertTrue(store.hasThumbnail(pid: 42, windowID: 7))
        XCTAssertTrue(store.isFresh(pid: 42, windowID: 7, lifespan: 60, now: capturedAt.addingTimeInterval(30)))
        XCTAssertFalse(store.isFresh(pid: 42, windowID: 7, lifespan: 60, now: capturedAt.addingTimeInterval(61)))
        XCTAssertNotNil(store.loadImage(pid: 42, windowID: 7))
    }

    func testRemoveDeletesFiles() async throws {
        let image = makeTestCGImage()
        await store.write(pid: 10, windowID: 3, cgImage: image, capturedAt: Date())
        XCTAssertTrue(store.hasThumbnail(pid: 10, windowID: 3))

        await store.remove(pid: 10, windowID: 3)
        XCTAssertFalse(store.hasThumbnail(pid: 10, windowID: 3))
    }

    func testLoadFallsBackToNewestCaptureWithMatchingTitle() async throws {
        let image = makeTestCGImage()
        let capturedAt = Date(timeIntervalSince1970: 5_000)
        await store.write(
            pid: 42,
            windowID: 100,
            cgImage: image,
            capturedAt: capturedAt,
            title: "Notes.md"
        )

        XCTAssertNotNil(store.loadImage(pid: 42, windowID: 999, title: "Notes.md"))
    }

    func testPruneExpiredRemovesStaleFiles() async throws {
        let image = makeTestCGImage()
        let old = Date(timeIntervalSince1970: 1_000)
        await store.write(pid: 99, windowID: 1, cgImage: image, capturedAt: old)
        XCTAssertTrue(store.hasThumbnail(pid: 99, windowID: 1))

        await store.pruneExpired(olderThan: Date(timeIntervalSince1970: 2_000))
        XCTAssertFalse(store.hasThumbnail(pid: 99, windowID: 1))
    }

    private func makeTestCGImage() -> CGImage {
        let context = CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return context.makeImage()!
    }
}
