import CoreGraphics
@testable import Platform
import XCTest

final class WindowScreenDetectorBorderConversionTests: XCTestCase {
    func testSecondaryDisplayCGToAppKitConversionPreservesWidth() {
        let primary = WindowControlScreen(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875)
        )
        let secondary = WindowControlScreen(
            id: 2,
            frame: CGRect(x: 1440, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 1440, y: 0, width: 1440, height: 875)
        )
        let detector = WindowScreenDetector(screens: [primary, secondary])
        let cgFrame = CGRect(x: 1500, y: 100, width: 800, height: 600)
        XCTAssertEqual(detector.screen(containing: cgFrame)?.id, 2)

        let appKitScreenFrame = CGRect(x: 1440, y: 0, width: 1440, height: 900)
        let converted = WindowScreenDetector.convertCGDisplayRectToAppKitCoordinates(
            cgRect: cgFrame,
            appKitScreenFrame: appKitScreenFrame,
            cgDisplayBounds: secondary.frame
        )
        XCTAssertEqual(converted.width, 800)
        XCTAssertEqual(converted.height, 600)
        XCTAssertEqual(converted.minX, 1500)
    }
}
