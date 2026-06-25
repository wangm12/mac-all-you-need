import XCTest
@testable import MacAllYouNeed

final class WindowHubEnumerationLogicTests: XCTestCase {
    func testTabCountIgnoresWindowFallbackRows() {
        let windowTarget = WindowHubTarget(
            id: .window(pid: 1, windowID: 10),
            kind: .window,
            pid: 1,
            bundleIdentifier: "com.example.app",
            appName: "Example",
            windowID: 10,
            windowTitle: "Example",
            tabTitle: nil,
            domain: nil,
            isMinimized: false,
            isActive: true,
            isPinned: false,
            isAudible: false,
            isPrivate: false,
            capabilities: .windowOnly,
            riskLevel: .low
        )
        let tabTarget = WindowHubTarget(
            id: .tab(pid: 1, windowID: 10, tabKey: "a"),
            kind: .tab,
            pid: 1,
            bundleIdentifier: "com.example.app",
            appName: "Example",
            windowID: 10,
            windowTitle: "Example",
            tabTitle: "Docs",
            domain: "example.com",
            isMinimized: false,
            isActive: false,
            isPinned: false,
            isAudible: false,
            isPrivate: false,
            capabilities: .browserAX,
            riskLevel: .medium
        )
        let section = WindowHubAppSection(
            id: "1",
            pid: 1,
            bundleIdentifier: "com.example.app",
            appName: "Example",
            windowGroups: [
                WindowHubWindowGroup(
                    id: "1-10",
                    windowID: 10,
                    title: "Example",
                    isMinimized: false,
                    isActive: true,
                    isHeavy: false,
                    visibleTargets: [windowTarget],
                    hiddenTabCount: 0,
                    capabilities: .windowOnly
                ),
                WindowHubWindowGroup(
                    id: "1-11",
                    windowID: 11,
                    title: "Browser",
                    isMinimized: false,
                    isActive: false,
                    isHeavy: false,
                    visibleTargets: [tabTarget, tabTarget],
                    hiddenTabCount: 1,
                    capabilities: .browserAX
                ),
            ],
            isBackgroundOnly: false
        )

        XCTAssertEqual(WindowHubSectionMetrics.tabCount(in: section), 3)
    }

    func testNamesMatchAcceptsSubstringTitles() {
        XCTAssertTrue(
            BrowserAppleScriptTabCache.namesMatch(
                "Mac All You Need — UI Replica - Google Chrome",
                "Mac All You Need — UI Replica"
            )
        )
    }

    func testNamesMatchRejectsPlaceholderWindowTitles() {
        XCTAssertFalse(BrowserAppleScriptTabCache.namesMatch("Window", "Google Chrome"))
    }
}
