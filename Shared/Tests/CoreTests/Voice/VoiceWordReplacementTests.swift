@testable import Core
import XCTest

final class VoiceWordReplacementTests: XCTestCase {
    func testAppliesCJKSubstringReplacement() {
        let entries = [
            VoiceDictionaryEntry.fixture(phrase: "海涛", replacement: "江涛")
        ]

        XCTAssertEqual(
            VoiceWordReplacement.apply("帮我改成海涛。", entries: entries),
            "帮我改成江涛。"
        )
    }

    func testAppliesLongestReplacementFirst() {
        let entries = [
            VoiceDictionaryEntry.fixture(phrase: "New", replacement: "Old"),
            VoiceDictionaryEntry.fixture(phrase: "New York", replacement: "NYC")
        ]

        XCTAssertEqual(
            VoiceWordReplacement.apply("Ship it to New York, not New Jersey.", entries: entries),
            "Ship it to NYC, not Old Jersey."
        )
    }

    func testLatinReplacementRespectsWordBoundaries() {
        let entries = [
            VoiceDictionaryEntry.fixture(phrase: "service", replacement: "svc")
        ]

        XCTAssertEqual(
            VoiceWordReplacement.apply("service services microservice service.", entries: entries),
            "svc services microservice svc."
        )
    }
}

private extension VoiceDictionaryEntry {
    static func fixture(phrase: String, replacement: String) -> VoiceDictionaryEntry {
        VoiceDictionaryEntry(
            id: UUID().uuidString,
            phrase: phrase,
            replacement: replacement,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }
}
