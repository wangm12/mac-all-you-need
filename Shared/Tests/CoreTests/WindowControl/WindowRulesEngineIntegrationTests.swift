import CoreGraphics
@testable import Core
import XCTest

final class WindowRulesEngineIntegrationTests: XCTestCase {
    func testTitlePatternIgnoreRule() {
        let engine = WindowRulesEngine(rules: [
            WindowRule(bundleID: "com.example.App", titlePattern: "Debug", action: .ignore)
        ])
        XCTAssertTrue(engine.shouldIgnore(bundleID: "com.example.App", title: "Debug Console"))
        XCTAssertFalse(engine.shouldIgnore(bundleID: "com.example.App", title: "Main Window"))
    }

    func testForceFloatingDisallowsSnapping() {
        let engine = WindowRulesEngine(rules: [
            WindowRule(bundleID: "com.example.App", action: .forceFloating)
        ])
        XCTAssertTrue(engine.allowsWindowControl(bundleID: "com.example.App", title: nil))
        XCTAssertFalse(engine.allowsSnapping(bundleID: "com.example.App", title: nil))
    }

    func testDefaultSnapAllowsSnapping() {
        let engine = WindowRulesEngine(rules: [
            WindowRule(bundleID: "com.example.App", action: .defaultSnap)
        ])
        XCTAssertTrue(engine.allowsSnapping(bundleID: "com.example.App", title: nil))
    }
}
