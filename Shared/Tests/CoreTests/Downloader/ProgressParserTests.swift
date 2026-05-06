@testable import Core
import XCTest

final class ProgressParserTests: XCTestCase {
    func testParsesPercentSpeedETA() {
        let line = "[download]  37.4% of    8.21MiB at  3.21MiB/s ETA 00:01"
        let p = ProgressParser.parse(line: line)
        XCTAssertNotNil(p)
        XCTAssertEqual(p?.fraction ?? 0, 0.374, accuracy: 0.001)
        XCTAssertEqual(p?.speedBytesPerSec ?? 0, 3.21 * 1024 * 1024, accuracy: 1024)
        XCTAssertEqual(p?.etaSeconds, 1)
        XCTAssertEqual(Double(p?.totalBytes ?? 0), 8.21 * 1024 * 1024, accuracy: 1024)
    }

    func testParsesCompletion() {
        let line = "[download] 100% of    8.21MiB in 00:02"
        XCTAssertEqual(ProgressParser.parse(line: line)?.fraction, 1.0)
    }

    func testIgnoresUnrelatedLines() {
        XCTAssertNil(ProgressParser.parse(line: "[info] downloaded 1 of 1 video"))
    }
}
