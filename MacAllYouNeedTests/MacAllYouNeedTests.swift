@testable import MacAllYouNeed
import AppKit
import Core
import XCTest

final class MacAllYouNeedTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true)
    }

    func testDownloadMetadataFallbackDerivesYoutubeThumbnail() {
        XCTAssertEqual(
            DownloadMetadataFallback.thumbnailURL(for: "https://www.youtube.com/watch?v=RkJBqhYz9GM"),
            "https://i.ytimg.com/vi/RkJBqhYz9GM/hqdefault.jpg"
        )
        XCTAssertEqual(
            DownloadMetadataFallback.thumbnailURL(for: "https://youtu.be/RkJBqhYz9GM?si=abc"),
            "https://i.ytimg.com/vi/RkJBqhYz9GM/hqdefault.jpg"
        )
    }

    func testDownloadMetadataFallbackDerivesTitleFromDestinationPath() {
        XCTAssertEqual(
            DownloadMetadataFallback.title(fromDestinationPath: "/Users/mingjie/Downloads/This Season FINALE Was ABSOLUTELY RIDICULOUS... - The Next Chapter.mp4"),
            "This Season FINALE Was ABSOLUTELY RIDICULOUS... - The Next Chapter"
        )
    }

    func testDownloadMetadataFallbackDoesNotOverwriteFetchedMetadata() {
        var record = DownloadRecord(
            url: "https://www.youtube.com/watch?v=RkJBqhYz9GM",
            title: "original",
            destinationPath: "/tmp/%(title)s.%(ext)s",
            state: .running
        )
        record.videoTitle = "Fetched title"
        record.thumbnailURL = "https://example.com/thumb.jpg"

        let updated = DownloadMetadataFallback.applyingFallbacks(
            to: record,
            destinationPath: "/Users/mingjie/Downloads/Derived title.mp4"
        )

        XCTAssertEqual(updated.videoTitle, "Fetched title")
        XCTAssertEqual(updated.thumbnailURL, "https://example.com/thumb.jpg")
        XCTAssertEqual(updated.destinationPath, "/Users/mingjie/Downloads/Derived title.mp4")
    }

    func testDownloadMetadataFallbackPersistsConcreteDestinationPath() {
        let record = DownloadRecord(
            url: "https://www.youtube.com/watch?v=RkJBqhYz9GM",
            title: "original",
            destinationPath: "/tmp/%(title)s.%(ext)s",
            state: .running
        )

        let updated = DownloadMetadataFallback.applyingFallbacks(
            to: record,
            destinationPath: "/Users/mingjie/Downloads/Real file.mp4"
        )

        XCTAssertEqual(updated.destinationPath, "/Users/mingjie/Downloads/Real file.mp4")
    }

    func testDownloadMetadataFallbackIgnoresTemplateDestinationPath() {
        let record = DownloadRecord(
            url: "https://www.youtube.com/watch?v=RkJBqhYz9GM",
            title: "original",
            destinationPath: "/tmp/%(title)s.%(ext)s",
            state: .running
        )

        let updated = DownloadMetadataFallback.applyingFallbacks(
            to: record,
            destinationPath: "/tmp/%(title)s.%(ext)s"
        )

        XCTAssertEqual(updated.destinationPath, "/tmp/%(title)s.%(ext)s")
    }

    func testNotificationPillsUsePlainCapsuleWithoutOuterShadow() {
        XCTAssertFalse(MAYNNotificationPillPresentation.hasOuterShadow)
        XCTAssertEqual(MAYNNotificationPillPresentation.iconSize, 14)
        XCTAssertEqual(MAYNNotificationPillPresentation.titleFontSize, 14)
        XCTAssertEqual(MAYNNotificationPillPresentation.detailFontSize, 12)
        XCTAssertEqual(MAYNNotificationPillPresentation.verticalPadding, 10)
        XCTAssertFalse(MAYNNotificationPillPresentation.hasIconBackground)
        XCTAssertFalse(MAYNNotificationPillPresentation.hasCapsuleStroke)
        XCTAssertEqual(MAYNNotificationPillPresentation.copyPanelHeight, 50)
    }

    func testSourceInfoPlistDeclaresAppIconForSystemPermissionPrompts() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plistURL = repoRoot
            .appendingPathComponent("MacAllYouNeed")
            .appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "AppIcon")
        XCTAssertEqual(plist["CFBundleIconName"] as? String, "AppIcon")
    }

    func testFloatingHUDLayerSitsAbovePanelsAndNativeDragPreviews() {
        let dragPreviewLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.draggingWindow)))

        XCTAssertGreaterThan(FloatingHUDWindowLayering.windowLevel.rawValue, NSWindow.Level.popUpMenu.rawValue)
        XCTAssertGreaterThan(FloatingHUDWindowLayering.windowLevel.rawValue, dragPreviewLevel.rawValue)
        XCTAssertTrue(FloatingHUDWindowLayering.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(FloatingHUDWindowLayering.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(FloatingHUDWindowLayering.collectionBehavior.contains(.stationary))
        XCTAssertTrue(FloatingHUDWindowLayering.collectionBehavior.contains(.ignoresCycle))
    }

    func testRunningDownloadBadgeReadsDownloading() {
        XCTAssertEqual(
            DownloadStatePresentation.badgeText(for: .running, isMerging: false),
            "Downloading"
        )
    }

    func testActiveDownloadsListFilterKeepsFailedItemsInQueue() {
        XCTAssertTrue(DownloadsListFilter.activeQueue.includes(.queued))
        XCTAssertTrue(DownloadsListFilter.activeQueue.includes(.running))
        XCTAssertTrue(DownloadsListFilter.activeQueue.includes(.paused))
        XCTAssertTrue(DownloadsListFilter.activeQueue.includes(.failed))
        XCTAssertFalse(DownloadsListFilter.activeQueue.includes(.completed))
    }

    func testCompletedDownloadsListFilterOnlyIncludesCompletedItems() {
        XCTAssertTrue(DownloadsListFilter.completed.includes(.completed))
        XCTAssertFalse(DownloadsListFilter.completed.includes(.queued))
        XCTAssertFalse(DownloadsListFilter.completed.includes(.running))
        XCTAssertFalse(DownloadsListFilter.completed.includes(.paused))
        XCTAssertFalse(DownloadsListFilter.completed.includes(.failed))
    }
}
