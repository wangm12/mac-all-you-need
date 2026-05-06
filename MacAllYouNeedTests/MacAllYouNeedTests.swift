@testable import MacAllYouNeed
import XCTest

final class MacAllYouNeedTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true)
    }

    func testCookieArgumentsUsePreparedCookieFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cookies-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("cookies.txt")
        let args = DownloadCoordinator.cookieArguments(cookieFileURL: url) { fileURL in
            try "# Netscape HTTP Cookie File\n".write(to: fileURL, atomically: true, encoding: .utf8)
        }

        XCTAssertEqual(args, ["--cookies", url.path])
    }

    func testCookieArgumentsFallBackWhenPreparationFails() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cookies.txt")
        let args = DownloadCoordinator.cookieArguments(cookieFileURL: url) { _ in
            throw CocoaError(.fileNoSuchFile)
        }

        XCTAssertEqual(args, [])
    }
}
