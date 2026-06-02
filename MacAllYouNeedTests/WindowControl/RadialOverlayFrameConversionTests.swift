import CoreGraphics
import Platform
@testable import MacAllYouNeed
import XCTest

@MainActor
final class RadialOverlayFrameConversionTests: XCTestCase {
    func testAppKitPointRoundTripsThroughCG() {
        let layout = [
            WindowScreenDetector.ScreenLayoutPair(
                appKitFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                cgBounds: CGRect(x: 0, y: 0, width: 1440, height: 900)
            )
        ]
        let original = CGPoint(x: 400, y: 300)
        let appKit = WindowScreenDetector.appKitPoint(fromCG: original, layout: layout)
        let roundTrip = WindowScreenDetector.cgPoint(fromAppKit: appKit, layout: layout)
        XCTAssertEqual(roundTrip.x, original.x, accuracy: 0.5)
        XCTAssertEqual(roundTrip.y, original.y, accuracy: 0.5)
    }
}
