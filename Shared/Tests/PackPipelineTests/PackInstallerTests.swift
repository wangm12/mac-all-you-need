import XCTest
import FeatureCore
@testable import PackPipeline

final class PackInstallerTests: XCTestCase {
    private var workspace: URL!
    private var fixturesDir: URL!

    override func setUp() {
        super.setUp()
        workspace = FileManager.default.temporaryDirectory.appendingPathComponent("PackInstallerTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        fixturesDir = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workspace)
        super.tearDown()
    }

    private func makePackEntry() throws -> FeaturePackManifest.PackEntry {
        let zip = fixturesDir.appendingPathComponent("happy-pack.zip")
        let zipSha = try SHA256Hasher.hex(ofFileAt: zip)
        let extractDir = workspace.appendingPathComponent("compute-shas")
        defer { try? FileManager.default.removeItem(at: extractDir) }
        _ = try ZipExtractor.extract(zipFileURL: zip, into: extractDir, allowedFiles: ["yt-dlp", "ffmpeg", "manifest.json"], maxTotalBytes: 1_000_000)
        let ytSha = try SHA256Hasher.hex(ofFileAt: extractDir.appendingPathComponent("yt-dlp"))
        let ffSha = try SHA256Hasher.hex(ofFileAt: extractDir.appendingPathComponent("ffmpeg"))
        let mfSha = try SHA256Hasher.hex(ofFileAt: extractDir.appendingPathComponent("manifest.json"))

        return FeaturePackManifest.PackEntry(
            version: "1.0.0",
            url: zip,
            zipSha256: zipSha,
            sizeBytes: 1024,
            files: [
                "yt-dlp": .init(sha256: ytSha, executable: true, maxBytes: 1024),
                "ffmpeg": .init(sha256: ffSha, executable: true, maxBytes: 1024),
                "manifest.json": .init(sha256: mfSha, executable: false, maxBytes: 1024),
            ],
            codesignRequirement: "anchor apple"  // skipped in tests via dryRunCodesign flag
        )
    }

    func testHappyInstallEndToEnd() throws {
        let entry = try makePackEntry()
        let zip = fixturesDir.appendingPathComponent("happy-pack.zip")
        let liveDir = workspace.appendingPathComponent("Features/downloader")

        let report = try PackInstaller.install(
            packZipURL: zip,
            entry: entry,
            featureLiveBaseDir: liveDir,
            stagingDir: workspace.appendingPathComponent("staging"),
            options: .init(dryRunCodesign: true)  // fake binaries aren't signed
        )

        XCTAssertEqual(report.installedVersion, "1.0.0")
        XCTAssertTrue(FileManager.default.fileExists(atPath: liveDir.appendingPathComponent("1.0.0/yt-dlp").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: liveDir.appendingPathComponent("1.0.0/ffmpeg").path))
        // No staging leftover
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("staging/1.0.0.staging").path))
    }

    func testRejectsZipShaMismatch() throws {
        let entry = try makePackEntry()
        let badEntry = FeaturePackManifest.PackEntry(
            version: entry.version, url: entry.url,
            zipSha256: "0000000000000000000000000000000000000000000000000000000000000000",
            sizeBytes: entry.sizeBytes, files: entry.files,
            codesignRequirement: entry.codesignRequirement
        )
        let zip = fixturesDir.appendingPathComponent("happy-pack.zip")

        XCTAssertThrowsError(try PackInstaller.install(
            packZipURL: zip, entry: badEntry,
            featureLiveBaseDir: workspace.appendingPathComponent("Features/downloader"),
            stagingDir: workspace.appendingPathComponent("staging"),
            options: .init(dryRunCodesign: true)
        )) { err in
            guard case PackPipelineError.wholeZipShaMismatch = err else {
                return XCTFail("expected wholeZipShaMismatch, got \(err)")
            }
        }
    }

    func testRejectsPerFileShaMismatch() throws {
        let entry = try makePackEntry()
        var badFiles = entry.files
        badFiles["yt-dlp"] = .init(sha256: "deadbeef", executable: true, maxBytes: 1024)
        let badEntry = FeaturePackManifest.PackEntry(
            version: entry.version, url: entry.url, zipSha256: entry.zipSha256,
            sizeBytes: entry.sizeBytes, files: badFiles, codesignRequirement: entry.codesignRequirement
        )
        let zip = fixturesDir.appendingPathComponent("happy-pack.zip")

        XCTAssertThrowsError(try PackInstaller.install(
            packZipURL: zip, entry: badEntry,
            featureLiveBaseDir: workspace.appendingPathComponent("Features/downloader"),
            stagingDir: workspace.appendingPathComponent("staging"),
            options: .init(dryRunCodesign: true)
        )) { err in
            guard case PackPipelineError.fileShaMismatch = err else {
                return XCTFail("expected fileShaMismatch, got \(err)")
            }
        }
        // Live dir must not exist
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("Features/downloader/1.0.0").path))
    }
}
