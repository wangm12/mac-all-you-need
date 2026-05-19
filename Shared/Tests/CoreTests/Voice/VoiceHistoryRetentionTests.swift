@testable import Core
import XCTest

final class VoiceHistoryRetentionTests: XCTestCase {
    func test_storageKeyRoundTrip_succeeds_for_all_cases() {
        for option in VoiceHistoryRetention.allCases {
            XCTAssertEqual(VoiceHistoryRetention(storageKey: option.storageKey), option)
        }
    }

    func test_storageKey_for_forever_is_forever() {
        XCTAssertEqual(VoiceHistoryRetention.forever.storageKey, "forever")
    }

    func test_maxAgeSeconds_forever_is_nil() {
        XCTAssertNil(VoiceHistoryRetention.forever.maxAgeSeconds)
    }

    func test_maxAgeSeconds_oneDay_is_86400() {
        XCTAssertEqual(VoiceHistoryRetention.days1.maxAgeSeconds, 86_400)
    }

    func test_maxAgeSeconds_thirtyDays_is_2_592_000() {
        XCTAssertEqual(VoiceHistoryRetention.days30.maxAgeSeconds, 2_592_000)
    }

    func test_init_unknownKey_fallsBackToForever() {
        XCTAssertEqual(VoiceHistoryRetention(storageKey: "nonsense"), .forever)
    }

    func test_displayTitle_isHumanReadable() {
        XCTAssertEqual(VoiceHistoryRetention.forever.displayTitle, "Forever")
        XCTAssertEqual(VoiceHistoryRetention.days1.displayTitle, "Last 1 day")
        XCTAssertEqual(VoiceHistoryRetention.days7.displayTitle, "Last 7 days")
    }
}
