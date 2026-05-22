import Platform
import XCTest

/// Snapshot-style tests for the FolderPreview data pipeline (FolderEnumerator +
/// FolderPreviewDisplay). These exercise the data transformation that feeds
/// QuickLookPreviewView without requiring a live Quick Look extension host.
///
/// The FolderPreview extension is a sandboxed app-extension target and cannot be
/// imported directly from MacAllYouNeedTests. These tests pin the shared-package
/// layer (Platform) that the extension consumes.
final class FolderPreviewRendererSnapshotTests: XCTestCase {
    // MARK: - Fixture helpers

    private func makeFixtureDirectory() throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FolderPreviewTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func createFile(in dir: URL, name: String, content: String = "x") throws {
        try content.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: - Tests

    func testEnumerateImmediateReturnsSortedEntries() async throws {
        let dir = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try createFile(in: dir, name: "zebra.txt", content: "z")
        try createFile(in: dir, name: "apple.png", content: "a")
        try createFile(in: dir, name: "mango.swift", content: "m")

        let inventory = try await FolderEnumerator.enumerateImmediate(url: dir, maxEntries: 500)

        XCTAssertEqual(inventory.entries.count, 3)
        XCTAssertFalse(inventory.isPartial)

        // FolderPreviewDisplay.sorted: directories first, then files alphabetically
        let sorted = FolderPreviewDisplay.sorted(inventory.entries)
        XCTAssertEqual(sorted.map(\.name), ["apple.png", "mango.swift", "zebra.txt"])
    }

    func testEnumerateImmediateTracksKinds() async throws {
        let dir = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try createFile(in: dir, name: "photo.jpg")
        try createFile(in: dir, name: "clip.mp4")
        try createFile(in: dir, name: "README.md")

        let inventory = try await FolderEnumerator.enumerateImmediate(url: dir, maxEntries: 500)

        XCTAssertEqual(inventory.breakdown[.images, default: 0], 1, "jpg should be images")
        XCTAssertEqual(inventory.breakdown[.videos, default: 0], 1, "mp4 should be videos")
    }

    func testDisplayKindForDirectory() throws {
        let entry = FolderEntry(
            name: "MyFolder",
            path: "/tmp/MyFolder",
            isDirectory: true,
            size: 0,
            modified: Date(),
            kind: .folder
        )
        let kind = FolderPreviewDisplay.displayKind(for: entry)
        XCTAssertFalse(kind.isEmpty)
    }

    func testDisplayKindForImageFile() throws {
        let entry = FolderEntry(
            name: "photo.png",
            path: "/tmp/photo.png",
            isDirectory: false,
            size: 1024,
            modified: Date(),
            kind: .images
        )
        let kind = FolderPreviewDisplay.displayKind(for: entry)
        XCTAssertFalse(kind.isEmpty)
    }

    func testCanGenerateThumbnailForImage() throws {
        let entry = FolderEntry(
            name: "photo.jpg",
            path: "/tmp/photo.jpg",
            isDirectory: false,
            size: 2048,
            modified: Date(),
            kind: .images
        )
        XCTAssertTrue(FolderPreviewDisplay.canGenerateThumbnail(for: entry))
    }

    func testCannotGenerateThumbnailForArchive() throws {
        let entry = FolderEntry(
            name: "backup.zip",
            path: "/tmp/backup.zip",
            isDirectory: false,
            size: 1024,
            modified: Date(),
            kind: .archives
        )
        XCTAssertFalse(FolderPreviewDisplay.canGenerateThumbnail(for: entry))
    }

    func testSortedPutsDirectoriesBeforeFiles() throws {
        let dir1 = FolderEntry(name: "zfolder", path: "/tmp/zfolder", isDirectory: true, size: 0, modified: Date(), kind: .folder)
        let file1 = FolderEntry(name: "afile.txt", path: "/tmp/afile.txt", isDirectory: false, size: 10, modified: Date(), kind: .documents)
        let file2 = FolderEntry(name: "bfile.txt", path: "/tmp/bfile.txt", isDirectory: false, size: 10, modified: Date(), kind: .documents)

        let sorted = FolderPreviewDisplay.sorted([file2, file1, dir1])
        XCTAssertEqual(sorted.first?.name, "zfolder", "Directories must precede files regardless of name sort order")
        XCTAssertEqual(sorted[1].name, "afile.txt")
        XCTAssertEqual(sorted[2].name, "bfile.txt")
    }

    func testPartialInventoryWhenMaxEntriesExceeded() async throws {
        let dir = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        for i in 0 ..< 5 {
            try createFile(in: dir, name: "file\(i).txt")
        }

        // maxEntries=3 should produce a partial inventory
        let inventory = try await FolderEnumerator.enumerateImmediate(url: dir, maxEntries: 3)
        XCTAssertTrue(inventory.isPartial)
        XCTAssertLessThanOrEqual(inventory.entries.count, 3)
    }
}
