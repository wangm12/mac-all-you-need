@testable import Core
import XCTest

final class DownloadDiskCleanupTests: XCTestCase {
    func testIsConcretePathRejectsYtdlpTemplate() {
        XCTAssertFalse(DownloadDiskCleanup.isConcretePath("/tmp/%(title)s.%(ext)s"))
        XCTAssertFalse(DownloadDiskCleanup.isConcretePath(""))
        XCTAssertFalse(DownloadDiskCleanup.isConcretePath("   "))
    }

    func testIsConcretePathAcceptsResolvedPaths() {
        XCTAssertTrue(DownloadDiskCleanup.isConcretePath("/tmp/My Video - Channel.mp4"))
        XCTAssertTrue(
            DownloadDiskCleanup.isConcretePath("/Users/me/Downloads/MacAllYouNeed/s09g - Videos/clip.mp4")
        )
    }

    func testCollectionFolderURLRequiresCollectionTitle() {
        var record = DownloadRecord(
            url: "https://www.douyin.com/video/1",
            title: "clip",
            destinationPath: "/tmp/a.mp4",
            state: .completed
        )
        record.collectionID = "c1"
        record.collectionTitle = "Creator Name"
        record.collectionKind = .douyinProfile

        let folder = DownloadDiskCleanup.collectionFolderURL(for: [record])
        XCTAssertNotNil(folder)
        XCTAssertTrue(folder?.lastPathComponent.contains("Creator Name") == true)
    }

    func testCollectionFolderURLWorksForYoutubePlaylistTitle() {
        var record = DownloadRecord(
            url: "https://www.youtube.com/watch?v=abc",
            title: "clip",
            destinationPath: "/tmp/a.mp4",
            state: .completed
        )
        record.collectionID = "c2"
        record.collectionTitle = "s09g - Videos"
        record.collectionKind = .multiURL

        let folder = DownloadDiskCleanup.collectionFolderURL(for: [record])
        XCTAssertEqual(folder?.lastPathComponent, "s09g - Videos")
    }

    func testInferredCollectionFolderUsesTemplateParentDirectory() throws {
        let collectionDir = try DownloadDestinationBuilder.outputDirectory(
            collectionTitle: "s09g - Videos",
            useCollectionSubfolder: true
        )
        let paths = [
            collectionDir.appendingPathComponent("%(title)s - %(uploader)s.%(ext)s").path,
            collectionDir.appendingPathComponent("%(title)s.%(ext)s").path
        ]
        let folder = DownloadDiskCleanup.inferredCollectionFolder(from: paths)
        XCTAssertEqual(folder?.standardizedFileURL, collectionDir.standardizedFileURL)
    }

    func testInferredCollectionFolderRejectsBaseDownloadDirectory() throws {
        let base = try DownloadDestinationBuilder.outputDirectory(
            collectionTitle: nil,
            useCollectionSubfolder: false
        )
        let template = base.appendingPathComponent("%(title)s - %(uploader)s.%(ext)s").path
        XCTAssertNil(DownloadDiskCleanup.inferredCollectionFolder(from: [template]))
    }

    func testResolvedCollectionFolderPrefersInferredPathOverTitleLookup() {
        var record = DownloadRecord(
            url: "https://www.youtube.com/watch?v=abc",
            title: "clip",
            destinationPath: "/Volumes/External/MAYN/Custom Playlist/%(title)s.%(ext)s",
            state: .completed
        )
        record.collectionID = "c3"
        record.collectionTitle = "Different Title"
        record.collectionKind = .multiURL

        let folder = DownloadDiskCleanup.resolvedCollectionFolder(
            paths: [record.destinationPath],
            records: [record]
        )
        XCTAssertEqual(folder?.lastPathComponent, "Custom Playlist")
    }
}
