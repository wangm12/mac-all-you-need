import XCTest
@testable import FeatureCore

final class FeatureIDTests: XCTestCase {
    func testAllCasesPresent() {
        let expected: Set<FeatureID> = [.clipboard, .folderPreview, .downloader, .voice]
        XCTAssertEqual(Set(FeatureID.allCases), expected)
    }

    func testRawValuesAreStable() {
        XCTAssertEqual(FeatureID.clipboard.rawValue, "clipboard")
        XCTAssertEqual(FeatureID.folderPreview.rawValue, "folderPreview")
        XCTAssertEqual(FeatureID.downloader.rawValue, "downloader")
        XCTAssertEqual(FeatureID.voice.rawValue, "voice")
    }

    func testCodableRoundTrip() throws {
        let encoded = try JSONEncoder().encode(FeatureID.clipboard)
        let decoded = try JSONDecoder().decode(FeatureID.self, from: encoded)
        XCTAssertEqual(decoded, .clipboard)
    }
}
