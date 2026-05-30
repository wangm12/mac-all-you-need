@testable import Core
import XCTest

final class SmartTextServiceTests: XCTestCase {
    func testDetectionJSONRoundTrip() throws {
        let d = Detection(type: .code(language: .swift), calculation: nil, linkClean: nil)
        let json = try d.encodedJSON()
        let back = try Detection.decode(json: json)
        XCTAssertEqual(back, d)
    }
}
