@testable import Platform
import XCTest

final class LibArchiveBackendTests: XCTestCase {
    func testListZipEntries() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("la-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let f1 = dir.appendingPathComponent("hello.txt")
        try "hi".write(to: f1, atomically: true, encoding: .utf8)
        let zipURL = dir.appendingPathComponent("test.zip")
        let proc = Process()
        proc.launchPath = "/usr/bin/zip"
        proc.arguments = ["-j", zipURL.path, f1.path]
        try proc.run(); proc.waitUntilExit()

        let backend = LibArchiveBackend()
        let entries = try backend.list(archiveURL: zipURL, limits: .default)
        XCTAssertTrue(entries.contains { $0.path.hasSuffix("hello.txt") })
    }

    func testRejectsTooManyEntries() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("la2-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for i in 0 ..< 3 {
            try "\(i)".write(to: dir.appendingPathComponent("\(i).txt"), atomically: true, encoding: .utf8)
        }
        let zipURL = dir.appendingPathComponent("test.zip")
        let proc = Process()
        proc.launchPath = "/usr/bin/zip"
        proc.arguments = ["-j", zipURL.path] + (0 ..< 3).map { dir.appendingPathComponent("\($0).txt").path }
        try proc.run(); proc.waitUntilExit()

        let limits = ArchiveSafety.Limits(
            maxEntries: 1,
            maxDepth: 64,
            maxTotalUncompressedBytes: 1024 * 1024 * 1024,
            maxPerFileBytes: 1024 * 1024 * 1024
        )
        let backend = LibArchiveBackend()
        XCTAssertThrowsError(try backend.list(archiveURL: zipURL, limits: limits))
    }
}
