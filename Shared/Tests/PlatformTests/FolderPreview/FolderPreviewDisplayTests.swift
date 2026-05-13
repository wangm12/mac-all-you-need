@testable import Platform
import XCTest

final class FolderPreviewDisplayTests: XCTestCase {
    func testSortedEntriesPutFoldersFirstAndUseNaturalNameOrder() {
        let entries = [
            entry("File 10.png", kind: .images),
            entry("Folder 2", isDirectory: true, kind: .folder),
            entry("File 2.png", kind: .images),
            entry("Folder 10", isDirectory: true, kind: .folder),
            entry("notes.txt", kind: .documents)
        ]

        let sorted = FolderPreviewDisplay.sorted(entries).map(\.name)

        XCTAssertEqual(sorted, ["Folder 2", "Folder 10", "File 2.png", "File 10.png", "notes.txt"])
    }

    func testDisplayKindUsesReadableLabels() {
        XCTAssertEqual(FolderPreviewDisplay.displayKind(for: entry("AppDelegate.swift", kind: .code)), "Swift source")
        XCTAssertEqual(FolderPreviewDisplay.displayKind(for: entry("Archive.zip", kind: .archives)), "ZIP archive")
        XCTAssertEqual(FolderPreviewDisplay.displayKind(for: entry("Photo.heic", kind: .images)), "HEIC image")
        XCTAssertEqual(FolderPreviewDisplay.displayKind(for: entry("Documents", isDirectory: true, kind: .folder)), "Folder")
    }

    func testThumbnailEligibilityIncludesCommonPreviewTypes() {
        XCTAssertTrue(FolderPreviewDisplay.canGenerateThumbnail(for: entry("Photo.jpg", kind: .images)))
        XCTAssertTrue(FolderPreviewDisplay.canGenerateThumbnail(for: entry("Vector.svg", kind: .images)))
        XCTAssertTrue(FolderPreviewDisplay.canGenerateThumbnail(for: entry("Manual.pdf", kind: .documents)))
        XCTAssertTrue(FolderPreviewDisplay.canGenerateThumbnail(for: entry("Clip.mov", kind: .videos)))
        XCTAssertFalse(FolderPreviewDisplay.canGenerateThumbnail(for: entry("main.swift", kind: .code)))
        XCTAssertFalse(FolderPreviewDisplay.canGenerateThumbnail(for: entry("Nested", isDirectory: true, kind: .folder)))
    }

    func testFilterTitlesMatchFolderPreviewControls() {
        XCTAssertEqual(FolderPreviewFilter.allCases.map(\.title), ["All", "Folders", "Images", "Docs", "Media"])
    }

    func testFilterMatchesPreviewKinds() {
        XCTAssertTrue(FolderPreviewDisplay.matches(kind: .folder, isDirectory: true, filter: .images))
        XCTAssertTrue(FolderPreviewDisplay.matches(kind: .images, isDirectory: false, filter: .images))
        XCTAssertFalse(FolderPreviewDisplay.matches(kind: .videos, isDirectory: false, filter: .images))

        XCTAssertTrue(FolderPreviewDisplay.matches(kind: .videos, isDirectory: false, filter: .media))
        XCTAssertTrue(FolderPreviewDisplay.matches(kind: .audio, isDirectory: false, filter: .media))
        XCTAssertFalse(FolderPreviewDisplay.matches(kind: .documents, isDirectory: false, filter: .media))

        XCTAssertTrue(FolderPreviewDisplay.matches(kind: .documents, isDirectory: false, filter: .documents))
        XCTAssertTrue(FolderPreviewDisplay.matches(kind: .code, isDirectory: false, filter: .documents))
        XCTAssertTrue(FolderPreviewDisplay.matches(kind: .archives, isDirectory: false, filter: .documents))
        XCTAssertFalse(FolderPreviewDisplay.matches(kind: .images, isDirectory: false, filter: .documents))
    }

    private func entry(
        _ name: String,
        isDirectory: Bool = false,
        kind: FolderEntryKind
    ) -> FolderEntry {
        FolderEntry(
            name: name,
            path: "/tmp/\(name)",
            isDirectory: isDirectory,
            size: isDirectory ? 0 : 1024,
            modified: Date(timeIntervalSince1970: 0),
            kind: kind
        )
    }
}
