@testable import Core
import XCTest

final class WindowActionTests: XCTestCase {
    func testMVPActionMetadata() {
        XCTAssertEqual(WindowAction.leftHalf.title, "Left half")
        XCTAssertEqual(WindowAction.restore.symbolName, "arrow.uturn.backward")
        XCTAssertTrue(WindowAction.mvpActions.contains(.maximize))
        XCTAssertFalse(WindowAction.mvpActions.contains { $0.rawValue == "tileAll" })
    }

    func testMvpActionsMatchAllCurrentCases() {
        XCTAssertEqual(WindowAction.mvpActions, WindowAction.allCases)
    }

    func testActionCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(WindowAction.almostMaximize)
        let decoded = try JSONDecoder().decode(WindowAction.self, from: data)

        XCTAssertEqual(decoded, .almostMaximize)
    }
}
