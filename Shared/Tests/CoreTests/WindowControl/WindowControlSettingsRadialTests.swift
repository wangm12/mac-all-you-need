import Core
import XCTest

final class WindowControlSettingsRadialTests: XCTestCase {
    func testRadialDefaultsAreOff() {
        let s = WindowControlSettings.default
        XCTAssertFalse(s.radialMenuEnabled)
        XCTAssertFalse(s.radialLockToCenter)
        XCTAssertFalse(s.radialCursorSelectionEnabled)
    }

    func testRadialRoundTripsThroughCoding() throws {
        var s = WindowControlSettings.default
        s.radialMenuEnabled = true
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(WindowControlSettings.self, from: data)
        XCTAssertTrue(decoded.radialMenuEnabled)
    }

    func testLegacyPayloadDecodesToDefaults() throws {
        var s = WindowControlSettings.default
        s.radialMenuEnabled = false
        let data = try JSONEncoder().encode(s)
        var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        dict.removeValue(forKey: "radialMenuEnabled")
        dict.removeValue(forKey: "radialLockToCenter")
        dict.removeValue(forKey: "radialCursorSelectionEnabled")
        let legacyData = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(WindowControlSettings.self, from: legacyData)
        XCTAssertFalse(decoded.radialMenuEnabled)
        XCTAssertFalse(decoded.radialLockToCenter)
        XCTAssertFalse(decoded.radialCursorSelectionEnabled)
    }
}
