@testable import Platform
import XCTest

final class SnippetExpanderTests: XCTestCase {
    func testWhitespaceExpansionSuppressesDelimiterAndDeletesOnlyTrigger() {
        var planner = SnippetExpansionPlanner { trigger in
            trigger == ";email" ? "mingjie.wang@uber.com" : nil
        }

        for character in ";email" {
            XCTAssertNil(planner.handle(character))
        }

        let plan = planner.handle(" ")

        XCTAssertEqual(
            plan,
            SnippetExpansionPlan(
                body: "mingjie.wang@uber.com",
                charactersToDelete: 6,
                suppressCurrentEvent: true
            )
        )
    }

    func testWhitespaceWithoutKnownTriggerDoesNotExpand() {
        var planner = SnippetExpansionPlanner { _ in nil }

        for character in ";missing" {
            XCTAssertNil(planner.handle(character))
        }

        XCTAssertNil(planner.handle(" "))
    }

    func testConfirmWithTabModeDoesNotExpandOnWhitespace() {
        var planner = SnippetExpansionPlanner(
            mode: .confirmWithTab,
            lookup: { trigger in trigger == ";email" ? "mingjie.wang@uber.com" : nil }
        )

        for character in ";email" {
            XCTAssertNil(planner.handle(character))
        }

        XCTAssertNil(planner.handle(" "))
    }

    func testConfirmWithTabModeExpandsOnBareTab() {
        var planner = SnippetExpansionPlanner(
            mode: .confirmWithTab,
            lookup: { trigger in trigger == ";email" ? "mingjie.wang@uber.com" : nil }
        )

        for character in ";email" {
            XCTAssertNil(planner.handle(character))
        }

        let plan = planner.handle("\t", keyCode: 48)

        XCTAssertEqual(
            plan,
            SnippetExpansionPlan(
                body: "mingjie.wang@uber.com",
                charactersToDelete: 6,
                suppressCurrentEvent: true
            )
        )
    }

    func testDisabledModeNeverExpands() {
        var planner = SnippetExpansionPlanner(
            mode: .disabled,
            lookup: { trigger in trigger == ";email" ? "mingjie.wang@uber.com" : nil }
        )

        for character in ";email" {
            XCTAssertNil(planner.handle(character))
        }

        XCTAssertNil(planner.handle(" "))
        XCTAssertNil(planner.handle("\t", keyCode: 48))
    }
}
