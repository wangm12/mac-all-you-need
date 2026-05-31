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

    @MainActor func testSetThumbnailPersists() {
        let cache = DockPreviewWindowCache()
        let entry = DockPreviewWindowEntry(
            id: 9, pid: 200, title: "Thumb", frame: .zero,
            thumbnail: nil, isMinimized: false, isOnScreen: true
        )
        _ = cache.update(entries: [entry], for: 200)
        let image = NSImage(size: NSSize(width: 10, height: 10))
        cache.setThumbnail(image, windowID: 9, pid: 200)
        XCTAssertNotNil(cache.entries(for: 200).first { $0.id == 9 }?.thumbnail)
    }
}
