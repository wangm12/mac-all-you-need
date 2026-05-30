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

    func testCleanLinkRemovesUTM() {
        let r = SmartTextService.cleanLink("https://example.com/p?id=5&utm_source=news&utm_medium=email")
        XCTAssertEqual(r?.cleaned, "https://example.com/p?id=5")
        XCTAssertEqual(r?.removedCount, 2)
    }
    func testCleanLinkRemovesKnownTrackers() {
        let r = SmartTextService.cleanLink("https://example.com/?fbclid=abc&gclid=xyz")
        XCTAssertEqual(r?.cleaned, "https://example.com/")
        XCTAssertEqual(r?.removedCount, 2)
    }
    func testCleanLinkNilWhenNothingToRemove() {
        XCTAssertNil(SmartTextService.cleanLink("https://example.com/p?id=5"))
    }
    func testCleanLinkNilForNonURL() {
        XCTAssertNil(SmartTextService.cleanLink("just some text"))
    }
    func testCleanLinkNilForNoQuery() {
        XCTAssertNil(SmartTextService.cleanLink("https://example.com/path"))
    }

    func testDetectSwift() {
        XCTAssertEqual(SmartTextService.detectCodeLanguage(in: "func add(a: Int, b: Int) -> Int { a + b }"), .swift)
    }
    func testDetectJavaScript() {
        XCTAssertEqual(SmartTextService.detectCodeLanguage(in: "const f = (x) => x * 2"), .javascript)
    }
    func testDetectPython() {
        XCTAssertEqual(SmartTextService.detectCodeLanguage(in: "def greet(name):\n    print(name)"), .python)
    }
    func testDetectSQL() {
        XCTAssertEqual(SmartTextService.detectCodeLanguage(in: "SELECT id, name FROM users WHERE id = 5"), .sql)
    }
    func testDetectHTML() {
        XCTAssertEqual(SmartTextService.detectCodeLanguage(in: "<div class=\"x\">hello</div>"), .html)
    }
    func testDetectShell() {
        XCTAssertEqual(SmartTextService.detectCodeLanguage(in: "#!/bin/bash\necho hi"), .shell)
    }
    func testDetectMarkdownIsNotCode() {
        XCTAssertNil(SmartTextService.detectCodeLanguage(in: "# Title\n- item one\n- item two"))
    }
    func testDetectPlainProseIsNotCode() {
        XCTAssertNil(SmartTextService.detectCodeLanguage(in: "This is just a plain sentence."))
    }
}
