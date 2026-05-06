import AppKit
@testable import Core
@testable import Platform
import XCTest

final class ThumbnailServiceTests: XCTestCase {
    func testReturnsThumbnailForImage() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("th-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("a.png")
        let img = NSImage(size: NSSize(width: 100, height: 100))
        img.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 100, height: 100).fill(); img.unlockFocus()
        try img.tiffRepresentation?.write(to: url)

        let cacheDir = dir.appendingPathComponent("cache")
        let svc = ThumbnailService(cacheRoot: cacheDir)
        let thumb = try await svc.thumbnail(for: url, size: CGSize(width: 64, height: 64))
        XCTAssertNotNil(thumb)
    }
}
