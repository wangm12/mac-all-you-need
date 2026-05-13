@testable import MacAllYouNeed
import Core
import XCTest

final class VoiceDictionaryPresentationTests: XCTestCase {
    func testSearchMatchesPhraseAndReplacementCaseInsensitively() {
        let entries = [
            entry(id: "1", phrase: "海涛", replacement: "江涛"),
            entry(id: "2", phrase: "deploy service", replacement: "production deploy")
        ]

        XCTAssertEqual(
            VoiceDictionaryPresentation.filtered(entries, query: "江", filter: .all).map(\.id),
            ["1"]
        )
        XCTAssertEqual(
            VoiceDictionaryPresentation.filtered(entries, query: "SERVICE", filter: .all).map(\.id),
            ["2"]
        )
    }

    func testAutoAddedFilterIsEmptyUntilDictionarySourceIsStored() {
        let entries = [
            entry(id: "1", phrase: "海涛", replacement: "江涛")
        ]

        XCTAssertEqual(VoiceDictionaryPresentation.filtered(entries, query: "", filter: .autoAdded), [])
        XCTAssertEqual(VoiceDictionaryPresentation.filtered(entries, query: "", filter: .manuallyAdded), entries)
    }

    private func entry(id: String, phrase: String, replacement: String) -> VoiceDictionaryEntry {
        VoiceDictionaryEntry(
            id: id,
            phrase: phrase,
            replacement: replacement,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
    }
}
