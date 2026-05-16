import XCTest
@testable import PackPipeline

final class ZipExtractorTests: XCTestCase {
    private var workspace: URL!
    private var fixturesDir: URL!

    override func setUp() {
        super.setUp()
        workspace = FileManager.default.temporaryDirectory.appendingPathComponent("ZipExtractorTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        fixturesDir = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workspace)
        super.tearDown()
    }

    func testHappyExtract() throws {
        let zip = fixturesDir.appendingPathComponent("happy-pack.zip")
        let allow: Set<String> = ["yt-dlp", "ffmpeg", "manifest.json"]
        let result = try ZipExtractor.extract(zipFileURL: zip, into: workspace, allowedFiles: allow, maxTotalBytes: 1_000_000)
        XCTAssertEqual(Set(result.extractedFiles), allow)
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("yt-dlp").path))
    }

    func testRejectsZipSlip() throws {
        let zip = fixturesDir.appendingPathComponent("zipslip-pack.zip")
        XCTAssertThrowsError(try ZipExtractor.extract(zipFileURL: zip, into: workspace, allowedFiles: ["escape.txt"], maxTotalBytes: 1000)) { error in
            guard case PackPipelineError.zipSlipDetected = error else {
                return XCTFail("expected zipSlipDetected, got \(error)")
            }
        }
    }

    func testRejectsSymlink() throws {
        let zip = fixturesDir.appendingPathComponent("symlink-pack.zip")
        XCTAssertThrowsError(try ZipExtractor.extract(zipFileURL: zip, into: workspace, allowedFiles: ["yt-dlp"], maxTotalBytes: 1000)) { error in
            guard case PackPipelineError.symlinkInZip = error else {
                return XCTFail("expected symlinkInZip, got \(error)")
            }
        }
    }

    func testRejectsUnexpectedFile() throws {
        let zip = fixturesDir.appendingPathComponent("unexpected-file-pack.zip")
        XCTAssertThrowsError(try ZipExtractor.extract(zipFileURL: zip, into: workspace, allowedFiles: ["yt-dlp"], maxTotalBytes: 1000)) { error in
            guard case PackPipelineError.unexpectedFile(let name) = error else {
                return XCTFail("expected unexpectedFile, got \(error)")
            }
            XCTAssertEqual(name, "malware.bin")
        }
    }

    func testRejectsZipBomb() throws {
        let zip = fixturesDir.appendingPathComponent("zipbomb-pack.zip")
        XCTAssertThrowsError(try ZipExtractor.extract(zipFileURL: zip, into: workspace, allowedFiles: ["yt-dlp"], maxTotalBytes: 1_000_000)) { error in
            guard case PackPipelineError.zipBomb = error else {
                return XCTFail("expected zipBomb, got \(error)")
            }
        }
    }
}
