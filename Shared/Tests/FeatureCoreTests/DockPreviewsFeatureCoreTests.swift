import XCTest
@testable import FeatureCore

final class DockPreviewsFeatureCoreTests: XCTestCase {
    func testScreenRecordingPermissionRawValueIsStable() throws {
        XCTAssertEqual(Permission.screenRecording.rawValue, "screenRecording")
        let data = try JSONEncoder().encode(Permission.screenRecording)
        let decoded = try JSONDecoder().decode(Permission.self, from: data)
        XCTAssertEqual(decoded, .screenRecording)
    }

    func testDockPreviewsFeatureIDExists() {
        XCTAssertTrue(FeatureID.allCases.contains(.dockPreviews))
    }
}
