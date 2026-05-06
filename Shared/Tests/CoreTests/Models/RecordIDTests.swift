@testable import Core
import XCTest

final class RecordIDTests: XCTestCase {
    func testGeneratedIDIs26Chars() {
        let id = RecordID.generate()
        XCTAssertEqual(id.rawValue.count, 26)
    }

    func testGeneratedIDsAreUnique() {
        var seen = Set<String>()
        for _ in 0 ..< 1000 {
            seen.insert(RecordID.generate().rawValue)
        }
        XCTAssertEqual(seen.count, 1000)
    }

    func testGeneratedIDsAreLexicographicallyOrderedByTime() {
        let earlier = RecordID.generate()
        Thread.sleep(forTimeInterval: 0.005)
        let later = RecordID.generate()
        XCTAssertLessThan(earlier.rawValue, later.rawValue)
    }

    func testRoundTripFromString() {
        let id = RecordID.generate()
        let parsed = RecordID(rawValue: id.rawValue)
        XCTAssertEqual(parsed, id)
    }

    func testRejectsInvalidLength() {
        XCTAssertNil(RecordID(rawValue: "TOO_SHORT"))
    }
}
