import XCTest
@testable import MacAllYouNeed

final class FolderBookmarkTests: XCTestCase {
    func testBookmarkCreationAndResolution() throws {
        let url = FileManager.default.temporaryDirectory
        let data = try FolderBookmark.create(for: url)
        XCTAssertFalse(data.isEmpty)
        let resolved = try FolderBookmark.resolve(data)
        XCTAssertEqual(resolved.resolvingSymlinksInPath(), url.resolvingSymlinksInPath())
    }
}
