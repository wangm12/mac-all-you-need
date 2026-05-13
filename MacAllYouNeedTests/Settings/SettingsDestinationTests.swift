@testable import MacAllYouNeed
import XCTest

final class SettingsDestinationTests: XCTestCase {
    func testMapsLegacyTabKeysToSidebarDestinations() {
        XCTAssertEqual(SettingsDestination.legacySelection("general"), .general)
        XCTAssertEqual(SettingsDestination.legacySelection("clipboard"), .clipboard)
        XCTAssertEqual(SettingsDestination.legacySelection("downloads"), .downloads)
        XCTAssertEqual(SettingsDestination.legacySelection("folderPreview"), .folderPreview)
        XCTAssertEqual(SettingsDestination.legacySelection("hotkeys"), .hotkeys)
        XCTAssertEqual(SettingsDestination.legacySelection("shortcuts"), .snippets)
        XCTAssertEqual(SettingsDestination.legacySelection("privacy"), .privacy)
        XCTAssertEqual(SettingsDestination.legacySelection("storage"), .storage)
        XCTAssertEqual(SettingsDestination.legacySelection("search"), .search)
        XCTAssertEqual(SettingsDestination.legacySelection("appearance"), .general)
        XCTAssertEqual(SettingsDestination.legacySelection("advanced"), .advanced)
        XCTAssertEqual(SettingsDestination.legacySelection("voice"), .voice)
    }

    func testMapsDeferredSyncAndSpikeToStableDestinations() {
        XCTAssertEqual(SettingsDestination.legacySelection("sync"), .advanced)
        XCTAssertEqual(SettingsDestination.legacySelection("voiceSpike"), .voice)
    }

    func testFallsBackToClipboardForUnknownLegacyKey() {
        XCTAssertEqual(SettingsDestination.legacySelection("missing"), .clipboard)
    }
}
