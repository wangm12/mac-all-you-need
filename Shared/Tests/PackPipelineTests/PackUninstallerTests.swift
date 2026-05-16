import XCTest
@testable import PackPipeline

final class PackUninstallerTests: XCTestCase {
    func testRemovesAllVersionDirectories() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("PackUninstallerTests-\(UUID()).downloader")
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base.appendingPathComponent("1.0.0"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: base.appendingPathComponent("0.9.0"), withIntermediateDirectories: true)

        try PackUninstaller.uninstall(featureLiveBaseDir: base)

        XCTAssertFalse(FileManager.default.fileExists(atPath: base.path))
    }

    func testNoOpWhenAbsent() {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("nonexistent-\(UUID())")
        XCTAssertNoThrow(try PackUninstaller.uninstall(featureLiveBaseDir: base))
    }
}
