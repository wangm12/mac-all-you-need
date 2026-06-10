import FeatureCore
import Foundation
import PackPipeline
import XCTest

final class BundledPackSeederTests: XCTestCase {
    func testDevPlaceholderDetection() {
        let entry = FeaturePackManifest.PackEntry(
            version: "1.0.0",
            url: URL(string: "https://github.com/<owner>/mac-all-you-need/releases/download/v2.0.0-dev/Downloader-1.0.0.zip")!,
            zipSha256: String(repeating: "0", count: 64),
            sizeBytes: 1,
            files: [:],
            codesignRequirement: "anchor apple generic"
        )
        XCTAssertTrue(entry.isDevPlaceholder)
    }

    func testSeedDownloaderFromBundleResources() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundledPackSeederTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let bundleResources = workspace.appendingPathComponent("Resources")
        let liveBase = workspace.appendingPathComponent("Features/downloader")
        try FileManager.default.createDirectory(at: bundleResources, withIntermediateDirectories: true)

        FileManager.default.createFile(
            atPath: bundleResources.appendingPathComponent("yt-dlp").path,
            contents: Data("yt-dlp".utf8)
        )
        FileManager.default.createFile(
            atPath: bundleResources.appendingPathComponent("ffmpeg").path,
            contents: Data("ffmpeg".utf8)
        )

        let entry = FeaturePackManifest.PackEntry(
            version: "1.0.0",
            url: URL(string: "https://example.com/Downloader-1.0.0.zip")!,
            zipSha256: String(repeating: "0", count: 64),
            sizeBytes: 1,
            files: [:],
            codesignRequirement: "anchor apple generic"
        )

        let report = try XCTUnwrap(
            BundledPackSeeder.seedIfPossible(
                featureID: .downloader,
                entry: entry,
                bundleResourcesURL: bundleResources,
                liveBaseDir: liveBase
            )
        )

        XCTAssertEqual(report.installedVersion, "1.0.0")
        XCTAssertTrue(BundledPackSeeder.isAlreadyInstalled(entry: entry, liveBaseDir: liveBase))
    }

    func testSeedReturnsNilWhenBundleBinariesMissing() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundledPackSeederTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let bundleResources = workspace.appendingPathComponent("Resources")
        let liveBase = workspace.appendingPathComponent("Features/downloader")
        try FileManager.default.createDirectory(at: bundleResources, withIntermediateDirectories: true)

        let entry = FeaturePackManifest.PackEntry(
            version: "1.0.0",
            url: URL(string: "https://example.com/Downloader-1.0.0.zip")!,
            zipSha256: String(repeating: "0", count: 64),
            sizeBytes: 1,
            files: [:],
            codesignRequirement: "anchor apple generic"
        )

        let report = try BundledPackSeeder.seedIfPossible(
            featureID: .downloader,
            entry: entry,
            bundleResourcesURL: bundleResources,
            liveBaseDir: liveBase
        )
        XCTAssertNil(report)
    }
}
