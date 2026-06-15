import Core
import XCTest

final class WindowSnapIntentConfigurationTests: XCTestCase {
    func testValidatedClampsOutOfRangeValues() {
        let config = WindowSnapIntentConfiguration(
            movementThreshold: 1,
            edgeThreshold: 100,
            cornerThreshold: 2,
            sideHalfThreshold: 500
        ).validated()

        XCTAssertEqual(config.movementThreshold, 4)
        XCTAssertEqual(config.edgeThreshold, 40)
        XCTAssertEqual(config.cornerThreshold, 4)
        XCTAssertEqual(config.sideHalfThreshold, 400)
    }

    func testValidatedPreservesInRangeValues() {
        let config = WindowSnapIntentConfiguration(
            movementThreshold: 20,
            edgeThreshold: 10,
            cornerThreshold: 30,
            sideHalfThreshold: 200
        ).validated()

        XCTAssertEqual(config.movementThreshold, 20)
        XCTAssertEqual(config.edgeThreshold, 10)
        XCTAssertEqual(config.cornerThreshold, 30)
        XCTAssertEqual(config.sideHalfThreshold, 200)
    }
}
