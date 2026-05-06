@testable import Core
import XCTest

final class EnvelopeTests: XCTestCase {
    func testMetadataCodableRoundTrip() throws {
        let id = RecordID.generate()
        let device = DeviceID.generate()
        let now = Date()
        let meta = EnvelopeMetadata(
            kind: .clipboardItem,
            id: id,
            created: now,
            modified: now,
            deviceID: device,
            lamport: 7
        )
        let data = try JSONEncoder().encode(meta)
        let decoded = try JSONDecoder().decode(EnvelopeMetadata.self, from: data)
        XCTAssertEqual(decoded, meta)
    }

    func testRecordKindRawValuesStable() {
        XCTAssertEqual(RecordKind.clipboardItem.rawValue, "clipboard_item")
        XCTAssertEqual(RecordKind.snippet.rawValue, "snippet")
        XCTAssertEqual(RecordKind.pinboard.rawValue, "pinboard")
        XCTAssertEqual(RecordKind.settings.rawValue, "settings")
        XCTAssertEqual(RecordKind.downloadHistory.rawValue, "download_history")
    }
}
