@testable import Core
import XCTest

final class SmartTextServiceTests: XCTestCase {
    func testDetectionJSONRoundTrip() throws {
        let d = Detection(type: .code(language: .swift), calculation: nil, linkClean: nil)
        let json = try d.encodedJSON()
        let back = try Detection.decode(json: json)
        XCTAssertEqual(back, d)
    }

    func testCalculateBasic() { XCTAssertEqual(SmartTextService.calculate("2+3*4")?.value, "14") }
    func testCalculateParensAndDecimals() { XCTAssertEqual(SmartTextService.calculate("(1.5+2.5)*2")?.value, "8") }
    func testCalculateDivByZeroIsSilent() { XCTAssertNil(SmartTextService.calculate("5/0")) }
    func testCalculateRejectsBareNumber() { XCTAssertNil(SmartTextService.calculate("42")) }
    func testCalculateRejectsPhone() { XCTAssertNil(SmartTextService.calculate("+1-415-555-2671")) }
    func testCalculateRejectsDate() { XCTAssertNil(SmartTextService.calculate("2026-05-30")) }
    func testCalculateRejectsOverLength() { XCTAssertNil(SmartTextService.calculate(String(repeating: "1+", count: 200) + "1")) }
    func testCalculatePower() { XCTAssertEqual(SmartTextService.calculate("2^3")?.value, "8") }
}
