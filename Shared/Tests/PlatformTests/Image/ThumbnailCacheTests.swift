@testable import Platform
import XCTest

final class ThumbnailCacheTests: XCTestCase {
    func testReturnsNilForUnknownKey() {
        let cache = ThumbnailCache()
        XCTAssertNil(cache.value(blobID: "nope", maxDim: 100))
    }

    func testStoresAndRetrievesByBlobIDAndMaxDim() {
        let cache = ThumbnailCache()
        let small = Data(repeating: 1, count: 10)
        let big = Data(repeating: 2, count: 100)
        cache.set(small, blobID: "abc", maxDim: 100)
        cache.set(big, blobID: "abc", maxDim: 500)
        XCTAssertEqual(cache.value(blobID: "abc", maxDim: 100), small)
        XCTAssertEqual(cache.value(blobID: "abc", maxDim: 500), big)
        XCTAssertNil(cache.value(blobID: "abc", maxDim: 999))
    }

    func testRemoveDropsEntryButLeavesOthers() {
        let cache = ThumbnailCache()
        cache.set(Data([1]), blobID: "a", maxDim: 100)
        cache.set(Data([2]), blobID: "b", maxDim: 100)
        cache.remove(blobID: "a")
        XCTAssertNil(cache.value(blobID: "a", maxDim: 100))
        XCTAssertEqual(cache.value(blobID: "b", maxDim: 100), Data([2]))
    }
}
