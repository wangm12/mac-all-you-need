@testable import MacAllYouNeed
import AppKit
import XCTest

final class DockSearchInputControllerTests: XCTestCase {
    func testPrintableTextAppendsToQuery() {
        let decision = DockSearchInputController.decide(
            currentQuery: "hel",
            keyCode: 0,
            characters: "l",
            modifiers: []
        )
        XCTAssertEqual(decision, .consume(newQuery: "hell"))
    }

    func testShiftedPrintableTextIsAccepted() {
        let decision = DockSearchInputController.decide(
            currentQuery: "A",
            keyCode: 0,
            characters: "B",
            modifiers: .shift
        )
        XCTAssertEqual(decision, .consume(newQuery: "AB"))
    }

    func testDeleteKeyDropsLastCharacter() {
        let decision = DockSearchInputController.decide(
            currentQuery: "hello",
            keyCode: 51,
            characters: "\u{7F}",
            modifiers: []
        )
        XCTAssertEqual(decision, .consume(newQuery: "hell"))
    }

    func testDeleteOnEmptyQueryFallsThroughToPassthrough() {
        let decision = DockSearchInputController.decide(
            currentQuery: "",
            keyCode: 51,
            characters: "\u{7F}",
            modifiers: []
        )
        XCTAssertEqual(decision, .passthrough)
    }

    func testCommandShortcutIsPassthrough() {
        let decision = DockSearchInputController.decide(
            currentQuery: "search",
            keyCode: 0,
            characters: "a",
            modifiers: .command
        )
        XCTAssertEqual(decision, .passthrough)
    }

    func testControlModifierIsPassthrough() {
        let decision = DockSearchInputController.decide(
            currentQuery: "search",
            keyCode: 0,
            characters: "n",
            modifiers: .control
        )
        XCTAssertEqual(decision, .passthrough)
    }

    func testNewlineCharacterIsPassthrough() {
        let decision = DockSearchInputController.decide(
            currentQuery: "abc",
            keyCode: 36,
            characters: "\n",
            modifiers: []
        )
        XCTAssertEqual(decision, .passthrough)
    }

    func testTypingASequenceBuildsTheExpectedQuery() {
        var query = ""
        let inputs: [(String, NSEvent.ModifierFlags)] = [
            ("f", []),
            ("o", []),
            ("o", []),
            (" ", []),
            ("b", []),
            ("a", []),
            ("r", [])
        ]
        for (character, modifiers) in inputs {
            let decision = DockSearchInputController.decide(
                currentQuery: query,
                keyCode: 0,
                characters: character,
                modifiers: modifiers
            )
            guard case .consume(let next) = decision else {
                return XCTFail("expected consume for character '\(character)'")
            }
            query = next
        }
        XCTAssertEqual(query, "foo bar")
    }
}
