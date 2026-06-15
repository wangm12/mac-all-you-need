import Core
import CoreGraphics
@testable import Platform
import XCTest

final class WindowControlMoveDiagnosticsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        #if DEBUG
        WindowControlMoveDiagnostics.resetForTesting()
        #endif
    }

    func testRecordAndReadLatestDiagnostics() {
        WindowControlMoveDiagnostics.record(axRoundTrips: 7, durationMilliseconds: 12.5)
        let latest = WindowControlMoveDiagnostics.latest
        XCTAssertEqual(latest.axRoundTrips, 7)
        XCTAssertEqual(latest.durationMilliseconds, 12.5)
    }
}
