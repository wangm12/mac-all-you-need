@testable import Core
import XCTest

final class SensitiveContentFilterTests: XCTestCase {
    func testLuhnValidCard() {
        // 4242 4242 4242 4242 is a known valid Luhn test number.
        XCTAssertTrue(SensitiveContentFilter.luhnValid("4242424242424242"))
    }
    func testLuhnInvalidNumber() {
        XCTAssertFalse(SensitiveContentFilter.luhnValid("1234567890123456"))
    }
    func testSkipsPaymentCardWithSpaces() {
        XCTAssertEqual(
            SensitiveContentFilter.shouldSkip(text: "4242 4242 4242 4242", windowTitle: nil, pasteboardTypes: []),
            .paymentCard
        )
    }
    func testSkipsPaymentCardWithDashes() {
        XCTAssertEqual(
            SensitiveContentFilter.shouldSkip(text: "card 4242-4242-4242-4242 here", windowTitle: nil, pasteboardTypes: []),
            .paymentCard
        )
    }
    func testSkipsSensitiveWindow() {
        XCTAssertEqual(
            SensitiveContentFilter.shouldSkip(text: "hello", windowTitle: "1Password - Login", pasteboardTypes: []),
            .sensitiveWindow
        )
    }
    func testSkipsConcealedType() {
        XCTAssertEqual(
            SensitiveContentFilter.shouldSkip(text: "hello", windowTitle: nil, pasteboardTypes: ["org.nspasteboard.ConcealedType"]),
            .concealed
        )
    }
    func testKeepsNormalText() {
        XCTAssertNil(SensitiveContentFilter.shouldSkip(text: "just a note", windowTitle: "Notes", pasteboardTypes: []))
    }
    func testKeepsShortDigitRun() {
        // 12 digits — below the 13-digit minimum, not a card.
        XCTAssertNil(SensitiveContentFilter.shouldSkip(text: "123456789012", windowTitle: nil, pasteboardTypes: []))
    }
}
