import XCTest
@testable import Core

final class FolderPathNormalizerTests: XCTestCase {
    func testFileURLStringToPOSIX() {
        XCTAssertEqual(FolderPathNormalizer.normalize("file:///Users/me/Docs/"), "/Users/me/Docs")
    }

    func testStripsTrailingSlash() {
        XCTAssertEqual(FolderPathNormalizer.normalize("/Users/me/Docs/"), "/Users/me/Docs")
    }

    func testKeepsRootSlash() {
        XCTAssertEqual(FolderPathNormalizer.normalize("/"), "/")
    }

    func testPercentEncodedSpaces() {
        XCTAssertEqual(FolderPathNormalizer.normalize("file:///Users/me/My%20Folder"), "/Users/me/My Folder")
    }

    func testRejectsEmpty() {
        XCTAssertNil(FolderPathNormalizer.normalize(""))
    }

    func testPlainPathPassthrough() {
        XCTAssertEqual(FolderPathNormalizer.normalize("/Users/me/Documents"), "/Users/me/Documents")
    }
}
