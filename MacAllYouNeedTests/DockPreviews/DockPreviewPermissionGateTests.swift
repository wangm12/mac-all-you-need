import XCTest
@testable import MacAllYouNeed

final class DockPreviewPermissionGateTests: XCTestCase {
    func testModeIsOneOfTwoValues() {
        let mode = DockPreviewPermissionGate.currentMode()
        XCTAssertTrue(mode == .fullPreview || mode == .titlesOnly)
    }
}
