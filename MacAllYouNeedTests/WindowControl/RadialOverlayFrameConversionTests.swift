import CoreGraphics
@testable import MacAllYouNeed
import XCTest

@MainActor
final class RadialOverlayFrameConversionTests: XCTestCase {
    func testAppKitPointRoundTripsThroughCG() {
        let original = CGPoint(x: 400, y: 300)
        let appKit = WindowControlCoordinator.appKitPoint(fromCG: original)
        let roundTrip = WindowControlCoordinator.cgPoint(fromAppKit: appKit)
        XCTAssertEqual(roundTrip.x, original.x, accuracy: 0.5)
        XCTAssertEqual(roundTrip.y, original.y, accuracy: 0.5)
    }
}
