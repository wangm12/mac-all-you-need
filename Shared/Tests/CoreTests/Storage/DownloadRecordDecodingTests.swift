import XCTest
@testable import Core

final class DownloadRecordDecodingTests: XCTestCase {
    func testDecodesOldPayloadWithoutRoutingFields() throws {
        let json = """
        {
          "id": { "rawValue": "01ARZ3NDEKTSV4RRFFQ69G5FAV" },
          "url": "https://example.com/watch?v=1",
          "title": "sample",
          "destinationPath": "/tmp/sample.mp4",
          "state": "queued",
          "lamport": 0,
          "bytesDownloaded": 0,
          "created": 1781066989641,
          "modified": 1781066989641
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let record = try decoder.decode(DownloadRecord.self, from: Data(json.utf8))
        XCTAssertEqual(record.url, "https://example.com/watch?v=1")
        XCTAssertFalse(record.nativeYoutubePlaylist)
        XCTAssertNil(record.mediaType)
        XCTAssertNil(record.customHeaders)
    }
}
