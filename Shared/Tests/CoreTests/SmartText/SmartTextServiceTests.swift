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

    func testClassifyColor() { XCTAssertEqual(SmartTextService.analyze(text: "#FF8800").type, .color) }
    func testClassifyURL() { XCTAssertEqual(SmartTextService.analyze(text: "https://example.com/x").type, .url) }
    func testClassifyEmail() { XCTAssertEqual(SmartTextService.analyze(text: "user@example.com").type, .email) }
    func testClassifyPhone() { XCTAssertEqual(SmartTextService.analyze(text: "+1 (415) 555-2671").type, .phone) }
    func testClassifyPlain() { XCTAssertEqual(SmartTextService.analyze(text: "hello world").type, .plain) }
    func testClassifyCode() {
        XCTAssertEqual(SmartTextService.analyze(text: "func f() { }").type, .code(language: .swift))
    }
    func testClassifyJWT() {
        // header {"alg":"HS256","typ":"JWT"} . payload {"a":1} . sig
        let header = Data("{\"alg\":\"HS256\",\"typ\":\"JWT\"}".utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let payload = Data("{\"a\":1}".utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        let jwt = "\(header).\(payload).signature"
        XCTAssertEqual(SmartTextService.analyze(text: jwt).type, .jwt)
    }
    func testAnalyzeAttachesCalculationAndLink() {
        XCTAssertEqual(SmartTextService.analyze(text: "2+2").calculation?.value, "4")
        XCTAssertEqual(SmartTextService.analyze(text: "https://x.com/?utm_source=a").linkClean?.removedCount, 1)
    }
}
