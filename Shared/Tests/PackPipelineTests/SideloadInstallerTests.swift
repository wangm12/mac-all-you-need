import XCTest
import FeatureCore
@testable import PackPipeline

final class SideloadInstallerTests: XCTestCase {
    func testSideloadAppliesSamePipeline() throws {
        let fixtures = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
        let zip = fixtures.appendingPathComponent("happy-pack.zip")
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("SideloadInstallerTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let zipSha = try SHA256Hasher.hex(ofFileAt: zip)
        let report = try SideloadInstaller.install(
            zipURL: zip,
            userProvidedZipSha256: zipSha,
            featurePackKey: "downloader",
            manifest: try testManifest(zipSha: zipSha, fixturesDir: fixtures),
            featureLiveBaseDir: workspace.appendingPathComponent("Features/downloader"),
            stagingDir: workspace.appendingPathComponent("staging"),
            options: .init(dryRunCodesign: true)
        )
        XCTAssertEqual(report.installedVersion, "1.0.0")
    }

    func testSideloadRejectsWrongUserSha() throws {
        let fixtures = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
        let zip = fixtures.appendingPathComponent("happy-pack.zip")
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("SideloadInstallerTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: workspace) }

        XCTAssertThrowsError(try SideloadInstaller.install(
            zipURL: zip,
            userProvidedZipSha256: "deadbeef",
            featurePackKey: "downloader",
            manifest: try testManifest(zipSha: SHA256Hasher.hex(ofFileAt: zip), fixturesDir: fixtures),
            featureLiveBaseDir: workspace.appendingPathComponent("Features/downloader"),
            stagingDir: workspace.appendingPathComponent("staging"),
            options: .init(dryRunCodesign: true)
        )) { err in
            guard case PackPipelineError.wholeZipShaMismatch = err else {
                return XCTFail("expected wholeZipShaMismatch, got \(err)")
            }
        }
    }

    private func testManifest(zipSha: String, fixturesDir: URL) throws -> FeaturePackManifest {
        let zip = fixturesDir.appendingPathComponent("happy-pack.zip")
        let extractDir = FileManager.default.temporaryDirectory.appendingPathComponent("manifest-build-\(UUID())")
        defer { try? FileManager.default.removeItem(at: extractDir) }
        _ = try ZipExtractor.extract(zipFileURL: zip, into: extractDir, allowedFiles: ["yt-dlp", "ffmpeg", "manifest.json"], maxTotalBytes: 1_000_000)
        let entry = FeaturePackManifest.PackEntry(
            version: "1.0.0", url: zip, zipSha256: zipSha, sizeBytes: 1024,
            files: [
                "yt-dlp": .init(sha256: try SHA256Hasher.hex(ofFileAt: extractDir.appendingPathComponent("yt-dlp")), executable: true, maxBytes: 1024),
                "ffmpeg": .init(sha256: try SHA256Hasher.hex(ofFileAt: extractDir.appendingPathComponent("ffmpeg")), executable: true, maxBytes: 1024),
                "manifest.json": .init(sha256: try SHA256Hasher.hex(ofFileAt: extractDir.appendingPathComponent("manifest.json")), executable: false, maxBytes: 1024),
            ],
            codesignRequirement: "anchor apple"
        )
        return FeaturePackManifest(schemaVersion: 1, wrapperVersion: "test", packs: ["downloader": entry])
    }
}
