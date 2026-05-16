import XCTest
@testable import FeatureCore

final class FeaturePackManifestDecodingTests: XCTestCase {
    func testValidManifest() throws {
        let json = """
        {
          "schemaVersion": 1,
          "wrapperVersion": "2.0.0",
          "packs": {
            "downloader": {
              "version": "1.0.0",
              "url": "https://github.com/owner/repo/releases/download/v2.0.0/Downloader-1.0.0.zip",
              "zipSha256": "abc",
              "sizeBytes": 200,
              "files": {
                "yt-dlp": { "sha256": "111", "executable": true, "maxBytes": 50 },
                "ffmpeg": { "sha256": "222", "executable": true, "maxBytes": 200 }
              },
              "codesignRequirement": "anchor apple generic and certificate leaf [subject.OU] = \\"TEAM\\""
            }
          }
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(FeaturePackManifest.self, from: json)
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.wrapperVersion, "2.0.0")
        XCTAssertEqual(manifest.packs.count, 1)

        let pack = manifest.packs["downloader"]!
        XCTAssertEqual(pack.version, "1.0.0")
        XCTAssertEqual(pack.zipSha256, "abc")
        XCTAssertEqual(pack.sizeBytes, 200)
        XCTAssertEqual(pack.files.count, 2)
        XCTAssertEqual(pack.files["yt-dlp"]?.sha256, "111")
        XCTAssertTrue(pack.files["yt-dlp"]!.executable)
        XCTAssertEqual(pack.files["yt-dlp"]?.maxBytes, 50)
    }

    func testRejectsMismatchedSchemaVersion() {
        let json = #"{"schemaVersion":2,"wrapperVersion":"1","packs":{}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try FeaturePackManifest.decode(from: json, expectedSchemaVersion: 1)) { error in
            XCTAssertTrue(error is FeaturePackManifest.DecodingFailure)
        }
    }

    func testRejectsMissingFields() {
        let json = #"{"schemaVersion":1}"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(FeaturePackManifest.self, from: json))
    }

    func testRejectsMissingPerFileSha() {
        let json = """
        {
          "schemaVersion": 1, "wrapperVersion": "1",
          "packs": { "downloader": {
            "version":"1","url":"https://x","zipSha256":"a","sizeBytes":1,
            "files": { "yt-dlp": { "executable": true, "maxBytes": 1 } },
            "codesignRequirement":"r"
          }}
        }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(FeaturePackManifest.self, from: json))
    }
}
