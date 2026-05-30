import AppKit
import XCTest
@testable import MacAllYouNeed

final class DockPreviewThumbnailCacheTests: XCTestCase {
    @MainActor func testGetReturnsNilBeforeSet() {
        let cache = DockPreviewThumbnailCache()
        XCTAssertNil(cache.get(windowID: 42))
    }

    @MainActor func testGetReturnsImageAfterSet() {
        let cache = DockPreviewThumbnailCache()
        let img = NSImage(size: NSSize(width: 100, height: 100))
        cache.set(windowID: 42, image: img)
        XCTAssertNotNil(cache.get(windowID: 42))
    }

    @MainActor func testExpiredEntryReturnsNil() {
        var now = Date()
        let cache = DockPreviewThumbnailCache(ttl: 1.0, clock: { now })
        let img = NSImage(size: NSSize(width: 100, height: 100))
        cache.set(windowID: 42, image: img)
        now = now.addingTimeInterval(2.0)
        XCTAssertNil(cache.get(windowID: 42))
    }
}
