import XCTest
@testable import MacAllYouNeed

final class WindowHubFuzzyMatcherTests: XCTestCase {
    func testPrefixMatchRanksHigherThanContains() {
        let targets = [
            sampleTarget(title: "Chrome", breadcrumb: "Chrome"),
            sampleTarget(title: "Cursor", breadcrumb: "Cursor"),
        ]
        let results = WindowHubFuzzyMatcher.filter(targets: targets, query: "cur")
        XCTAssertEqual(results.first?.displayTitle, "Cursor")
    }

    func testEmptyQueryReturnsAllTargets() {
        let targets = [sampleTarget(title: "A", breadcrumb: "A"), sampleTarget(title: "B", breadcrumb: "B")]
        XCTAssertEqual(WindowHubFuzzyMatcher.filter(targets: targets, query: "").count, 2)
    }

    private func sampleTarget(title: String, breadcrumb: String) -> WindowHubTarget {
        WindowHubTarget(
            id: WindowHubTargetID(raw: title),
            kind: .window,
            pid: 1,
            bundleIdentifier: nil,
            appName: title,
            windowID: 1,
            windowTitle: title,
            tabTitle: nil,
            domain: nil,
            isMinimized: false,
            isActive: false,
            isPinned: false,
            isAudible: false,
            isPrivate: false,
            capabilities: .windowOnly,
            riskLevel: .low
        )
    }
}
