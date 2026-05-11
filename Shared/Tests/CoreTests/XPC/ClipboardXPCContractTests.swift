@testable import Core
import XCTest

final class ClipboardXPCContractTests: XCTestCase {
    func testProtocolHasRequiredSelectors() {
        let p = ClipboardXPCProtocol.self as Protocol
        XCTAssertNotNil(p)
        _ = ClipboardXPCList(items: [], nextPageToken: nil)
    }

    func testMetaForwardRoundtripPreservesAllFields() throws {
        let original = ClipboardXPCMeta(
            id: "abc",
            modified: Date(timeIntervalSince1970: 1_700_000_000),
            kind: "clipboardItem",
            preview: "hi",
            sourceAppBundleID: "com.apple.Safari",
            imageWidth: 320,
            imageHeight: 200,
            imageBlobID: "blob-1"
        )
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        original.encode(with: coder)
        let data = coder.encodedData

        let decoder = try NSKeyedUnarchiver(forReadingFrom: data)
        decoder.requiresSecureCoding = true
        guard let decoded = ClipboardXPCMeta(coder: decoder) else {
            XCTFail("decode failed")
            return
        }
        XCTAssertEqual(decoded.id, "abc")
        XCTAssertEqual(decoded.modified, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(decoded.kind, "clipboardItem")
        XCTAssertEqual(decoded.preview, "hi")
        XCTAssertEqual(decoded.sourceAppBundleID, "com.apple.Safari")
        XCTAssertEqual(decoded.imageWidth, 320)
        XCTAssertEqual(decoded.imageHeight, 200)
        XCTAssertEqual(decoded.imageBlobID, "blob-1")
    }

    func testMetaDecodesLegacyPayloadMissingNewFields() throws {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        coder.encode("legacy" as NSString, forKey: "id")
        coder.encode(Date(timeIntervalSince1970: 1) as NSDate, forKey: "modified")
        coder.encode("clipboardItem" as NSString, forKey: "kind")
        coder.encode("legacy preview" as NSString, forKey: "preview")
        let data = coder.encodedData

        let decoder = try NSKeyedUnarchiver(forReadingFrom: data)
        decoder.requiresSecureCoding = true
        guard let decoded = ClipboardXPCMeta(coder: decoder) else {
            XCTFail("legacy decode failed")
            return
        }
        XCTAssertEqual(decoded.id, "legacy")
        XCTAssertEqual(decoded.preview, "legacy preview")
        XCTAssertNil(decoded.sourceAppBundleID)
        XCTAssertEqual(decoded.imageWidth, 0)
        XCTAssertEqual(decoded.imageHeight, 0)
        XCTAssertNil(decoded.imageBlobID)
    }
}
