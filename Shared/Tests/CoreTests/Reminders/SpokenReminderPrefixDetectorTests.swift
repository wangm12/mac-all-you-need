@testable import Core
import XCTest

final class SpokenReminderPrefixDetectorTests: XCTestCase {
    func testRemindMeToIsDetected() {
        XCTAssertTrue(SpokenReminderPrefixDetector.isReminder("Remind me to buy milk"))
    }

    func testNonReminderReturnsFalse() {
        XCTAssertFalse(SpokenReminderPrefixDetector.isReminder("The meeting is at 3pm"))
    }

    func testStripsPrefix() {
        XCTAssertEqual(SpokenReminderPrefixDetector.strippingPrefix("Remind me to buy milk"), "buy milk")
    }

    func testCaseInsensitive() {
        XCTAssertTrue(SpokenReminderPrefixDetector.isReminder("REMIND ME TO send email"))
    }
}
