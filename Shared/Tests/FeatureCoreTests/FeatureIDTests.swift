import XCTest
@testable import FeatureCore

final class FeatureIDTests: XCTestCase {
    func testAllCasesPresent() {
        let expected: Set<FeatureID> = [
            .clipboard,
            .folderPreview,
            .downloader,
            .voice,
            .windowLayouts,
            .windowGrab,
            .clipboardSmartText,
            .folderHistory,
            .voiceReminders,
            .aiFileOrganizer,
            .windowHub
        ]
        XCTAssertEqual(Set(FeatureID.allCases), expected)
    }

    func testRawValuesAreStable() {
        XCTAssertEqual(FeatureID.clipboard.rawValue, "clipboard")
        XCTAssertEqual(FeatureID.folderPreview.rawValue, "folderPreview")
        XCTAssertEqual(FeatureID.downloader.rawValue, "downloader")
        XCTAssertEqual(FeatureID.voice.rawValue, "voice")
        XCTAssertEqual(FeatureID.windowLayouts.rawValue, "windowLayouts")
        XCTAssertEqual(FeatureID.windowGrab.rawValue, "windowGrab")
    }

    func testCodableRoundTrip() throws {
        let encoded = try JSONEncoder().encode(FeatureID.clipboard)
        let decoded = try JSONDecoder().decode(FeatureID.self, from: encoded)
        XCTAssertEqual(decoded, .clipboard)
    }
}
