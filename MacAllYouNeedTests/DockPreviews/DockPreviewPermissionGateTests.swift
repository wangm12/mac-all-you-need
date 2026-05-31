import XCTest
@testable import MacAllYouNeed

final class DockPreviewPermissionGateTests: XCTestCase {
    func testModeIsOneOfTwoValues() {
        let mode = DockPreviewPermissionGate.currentMode()
        XCTAssertTrue(mode == .fullPreview || mode == .titlesOnly)
    }

    func testShowThumbnailsOffForcesTitlesOnly() {
        var settings = DockPreviewSettings.default
        settings.showThumbnails = false
        XCTAssertEqual(DockPreviewPermissionGate.currentMode(settings: settings), .titlesOnly)
    }
}
