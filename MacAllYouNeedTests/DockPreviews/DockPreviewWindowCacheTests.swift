import AppKit
import XCTest
@testable import MacAllYouNeed

final class DockPreviewWindowCacheTests: XCTestCase {
    func testEntryEqualityIgnoresThumbnail() {
        let a = DockPreviewWindowEntry(
            id: 1, pid: 100, title: "Window A", frame: .zero,
            thumbnail: nil, isMinimized: false, isOnScreen: true
        )
        var b = a
        b.thumbnail = NSImage()
        XCTAssertEqual(a, b)
    }

    @MainActor func testUpdateReturnsDiff() {
        let cache = DockPreviewWindowCache()
        let entry = DockPreviewWindowEntry(
            id: 1, pid: 100, title: "A", frame: .zero,
            thumbnail: nil, isMinimized: false, isOnScreen: true
        )
        let diff1 = cache.update(entries: [entry], for: 100)
        XCTAssertEqual(diff1.added.count, 1)
        XCTAssertEqual(diff1.removed.count, 0)
        let diff2 = cache.update(entries: [], for: 100)
        XCTAssertEqual(diff2.removed.count, 1)
    }

    @MainActor func testUpdatePreservesCaptureTimestamp() {
        let cache = DockPreviewWindowCache()
        var entry = DockPreviewWindowEntry(
            id: 3, pid: 100, title: "Chrome", frame: .zero,
            thumbnail: nil, isMinimized: false, isOnScreen: true
        )
        let capturedAt = Date(timeIntervalSince1970: 1_500)
        entry.thumbnailCapturedAt = capturedAt
        _ = cache.update(entries: [entry], for: 100)

        var refresh = DockPreviewWindowEntry(
            id: 3, pid: 100, title: "Chrome", frame: .zero,
            thumbnail: nil, isMinimized: false, isOnScreen: true
        )
        _ = cache.update(entries: [refresh], for: 100)
        XCTAssertEqual(cache.readCached(pid: 100).first { $0.id == 3 }?.thumbnailCapturedAt, capturedAt)
        XCTAssertNil(cache.readCached(pid: 100).first { $0.id == 3 }?.thumbnail)
    }

    @MainActor func testRecordThumbnailCapturedPersistsMetadataOnly() {
        let cache = DockPreviewWindowCache()
        let entry = DockPreviewWindowEntry(
            id: 9, pid: 200, title: "Thumb", frame: .zero,
            thumbnail: nil, isMinimized: false, isOnScreen: true
        )
        _ = cache.update(entries: [entry], for: 200)
        let capturedAt = Date(timeIntervalSince1970: 1_000)
        cache.recordThumbnailCaptured(windowID: 9, pid: 200, capturedAt: capturedAt)
        let stored = cache.entries(for: 200).first { $0.id == 9 }
        XCTAssertNil(stored?.thumbnail)
        XCTAssertEqual(stored?.thumbnailCapturedAt, capturedAt)
    }

    @MainActor func testFreshWindowIDsUsesDiskStore() async {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("dock-cache-fresh-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let diskStore = DockPreviewThumbnailDiskStore(rootURL: tempRoot)
        let cache = DockPreviewWindowCache(diskStore: diskStore)
        let entry = DockPreviewWindowEntry(
            id: 5, pid: 100, title: "Fresh", frame: .zero,
            thumbnail: nil, isMinimized: false, isOnScreen: true
        )
        _ = cache.update(entries: [entry], for: 100)

        let now = Date(timeIntervalSince1970: 2_000)
        let image = makeTestCGImage()
        await diskStore.write(pid: 100, windowID: 5, cgImage: image, capturedAt: now)

        XCTAssertTrue(cache.freshWindowIDs(pid: 100, lifespan: 30, now: now.addingTimeInterval(10)).contains(5))
        XCTAssertFalse(cache.freshWindowIDs(pid: 100, lifespan: 30, now: now.addingTimeInterval(31)).contains(5))
    }

    private func makeTestCGImage() -> CGImage {
        let context = CGContext(
            data: nil,
            width: 4,
            height: 4,
            bitsPerComponent: 8,
            bytesPerRow: 16,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return context.makeImage()!
    }
}
