import XCTest
@testable import MacAllYouNeed

final class DockDockFolderItemResolverTests: XCTestCase {
    func testResolvesDownloadsWhenAXURLIsFinderApp() {
        let finderApp = URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications/Finder.app")
        let resolved = DockDockFolderItemResolver.resolveFolderURL(axURL: finderApp, title: "Downloads")
        XCTAssertNotNil(resolved)
        XCTAssertTrue(resolved?.lastPathComponent == "Downloads" || resolved?.path.contains("Downloads") == true)
    }

    func testResolvesApplicationsFolder() {
        let resolved = DockDockFolderItemResolver.resolveFolderURL(axURL: nil, title: "Applications")
        XCTAssertEqual(resolved?.path, "/Applications")
    }

    func testRejectsApplicationBundleWithoutKnownTitle() {
        let appURL = URL(fileURLWithPath: "/Applications/Safari.app")
        XCTAssertNil(DockDockFolderItemResolver.resolveFolderURL(axURL: appURL, title: "Safari"))
    }

    func testAcceptsRealDirectoryURL() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let resolved = DockDockFolderItemResolver.resolveFolderURL(axURL: temp, title: "Temp")
        XCTAssertEqual(resolved?.standardizedFileURL, temp.standardizedFileURL)
    }
}
