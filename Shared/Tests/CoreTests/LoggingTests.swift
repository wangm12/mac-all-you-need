@testable import Core
import os
import XCTest

final class LoggingTests: XCTestCase {
    func testSubsystemPrefix() {
        XCTAssertEqual(Logging.subsystem(for: "storage"), "com.macallyouneed.storage")
    }
}
