import AppKit
import XCTest
@testable import MacAllYouNeed

@MainActor
final class DockPreviewVisibleThumbnailCacheTests: XCTestCase {
    func testHydrateUsesInMemoryThumbnailAndReloadsAfterEvict() async {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("dock-visible-lru-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let diskStore = DockPreviewThumbnailDiskStore(rootURL: tempRoot)
        let lru = DockPreviewVisibleThumbnailCache(diskStore: diskStore)
        let image = makeTestCGImage()
        await diskStore.write(pid: 1, windowID: 10, cgImage: image, capturedAt: Date())
        let prefetched = await diskStore.loadIfPresentAsync(pid: 1, windowID: 10)

        let entry = DockPreviewWindowEntry(
            id: 10, pid: 1, title: "A", frame: .zero,
            thumbnail: prefetched, isMinimized: false, isOnScreen: true
        )
        let hydrated = lru.hydrate([entry])
        XCTAssertNotNil(hydrated.first?.thumbnail)

        lru.evictAll()
        let afterEvict = lru.hydrate([entry])
        XCTAssertNotNil(afterEvict.first?.thumbnail)
    }

    func testHydrateDoesNotSyncLoadFromDiskWhenThumbnailMissing() async {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("dock-visible-lru-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let diskStore = DockPreviewThumbnailDiskStore(rootURL: tempRoot)
        let lru = DockPreviewVisibleThumbnailCache(diskStore: diskStore)
        let image = makeTestCGImage()
        await diskStore.write(pid: 1, windowID: 10, cgImage: image, capturedAt: Date())

        let entry = DockPreviewWindowEntry(
            id: 10, pid: 1, title: "A", frame: .zero,
            thumbnail: nil, isMinimized: false, isOnScreen: true
        )
        let hydrated = lru.hydrate([entry])
        XCTAssertNil(hydrated.first?.thumbnail)
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
