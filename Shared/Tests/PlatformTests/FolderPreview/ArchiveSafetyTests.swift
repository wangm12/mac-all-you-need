@testable import Platform
import XCTest

final class ArchiveSafetyTests: XCTestCase {
    let limits = ArchiveSafety.Limits.default

    func testRejectsAbsolutePath() {
        XCTAssertThrowsError(try ArchiveSafety.validatePath("/etc/passwd", limits: limits))
    }

    func testRejectsTraversal() {
        XCTAssertThrowsError(try ArchiveSafety.validatePath("../etc/shadow", limits: limits))
        XCTAssertThrowsError(try ArchiveSafety.validatePath("foo/../../bar", limits: limits))
    }

    func testAcceptsRelativePath() {
        XCTAssertNoThrow(try ArchiveSafety.validatePath("dir/file.txt", limits: limits))
    }

    func testRejectsTooManyEntries() {
        XCTAssertThrowsError(try ArchiveSafety.checkEntryCount(limits.maxEntries + 1, limits: limits))
    }

    func testRejectsTooDeep() {
        XCTAssertThrowsError(try ArchiveSafety.validatePath(String(repeating: "a/", count: 100) + "x", limits: limits))
    }

    func testRejectsTooLargeUncompressed() {
        XCTAssertThrowsError(try ArchiveSafety.checkTotalUncompressed(limits.maxTotalUncompressedBytes + 1, limits: limits))
    }
}
