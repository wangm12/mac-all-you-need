import CoreGraphics
@testable import Platform
import XCTest

final class AppKitWindowIdentifierTests: XCTestCase {
    func testRejectsNegativeAppKitWindowNumbers() {
        XCTAssertFalse(AppKitWindowIdentifier.matches(windowNumber: -1, cgWindowID: 1))
    }

    func testRejectsZeroAppKitWindowNumber() {
        XCTAssertFalse(AppKitWindowIdentifier.matches(windowNumber: 0, cgWindowID: 0))
    }

    func testMatchesExactPositiveWindowNumber() {
        XCTAssertTrue(AppKitWindowIdentifier.matches(windowNumber: 42, cgWindowID: 42))
        XCTAssertFalse(AppKitWindowIdentifier.matches(windowNumber: 43, cgWindowID: 42))
    }
}
