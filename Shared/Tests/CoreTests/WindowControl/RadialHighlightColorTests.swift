import Core
import XCTest

final class RadialHighlightColorTests: XCTestCase {
    func testRoundTripsThroughCoding() throws {
        let color = RadialHighlightColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1)
        let data = try JSONEncoder().encode(color)
        let decoded = try JSONDecoder().decode(RadialHighlightColor.self, from: data)
        XCTAssertEqual(decoded, color)
    }
}
