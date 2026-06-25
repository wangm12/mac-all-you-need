import Core
import XCTest
@testable import MacAllYouNeed

final class WindowHubSnapshotCacheTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("WindowHubSnapshotCacheTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        AppGroup.containerURLOverride = tempRoot
    }

    override func tearDown() {
        AppGroup.containerURLOverride = nil
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    func testRoundTrip() {
        let target = WindowHubTarget(
            id: .tab(pid: 42, windowID: 7, tabKey: "as:1:2"),
            kind: .tab,
            pid: 42,
            bundleIdentifier: "com.google.Chrome",
            appName: "Chrome",
            windowID: 7,
            windowTitle: "Window",
            tabTitle: "Example",
            domain: "example.com",
            isMinimized: false,
            isActive: true,
            isPinned: false,
            isAudible: false,
            isPrivate: false,
            capabilities: .browserScript,
            riskLevel: .medium
        )
        let section = WindowHubAppSection(
            id: "42",
            pid: 42,
            bundleIdentifier: "com.google.Chrome",
            appName: "Chrome",
            windowGroups: [
                WindowHubWindowGroup(
                    id: "42-7",
                    windowID: 7,
                    title: "Example",
                    isMinimized: false,
                    isActive: true,
                    isHeavy: false,
                    visibleTargets: [target],
                    hiddenTabCount: 0,
                    capabilities: .browserScript
                ),
            ],
            isBackgroundOnly: false
        )
        let cached = WindowHubCachedSnapshot(
            capturedAt: Date(),
            currentTargetID: target.id,
            sections: [section],
            flatTargets: [target]
        )

        WindowHubSnapshotCache.save(cached)
        let loaded = WindowHubSnapshotCache.load()

        XCTAssertEqual(loaded?.sections.count, 1)
        XCTAssertEqual(loaded?.flatTargets.first?.tabTitle, "Example")
        XCTAssertEqual(loaded?.currentTargetID, target.id)
        XCTAssertEqual(loaded?.schemaVersion, WindowHubCachedSnapshot.currentSchemaVersion)
    }

    func testSaveRecomputesMismatchedFlatTargets() {
        let target = WindowHubTarget(
            id: .tab(pid: 42, windowID: 7, tabKey: "as:1:2"),
            kind: .tab,
            pid: 42,
            bundleIdentifier: "com.google.Chrome",
            appName: "Chrome",
            windowID: 7,
            windowTitle: "Window",
            tabTitle: "Example",
            domain: "example.com",
            isMinimized: false,
            isActive: true,
            isPinned: false,
            isAudible: false,
            isPrivate: false,
            capabilities: .browserScript,
            riskLevel: .medium
        )
        let windowTarget = WindowHubTarget(
            id: .window(pid: 42, windowID: 7),
            kind: .window,
            pid: 42,
            bundleIdentifier: "com.google.Chrome",
            appName: "Chrome",
            windowID: 7,
            windowTitle: "Window",
            tabTitle: nil,
            domain: nil,
            isMinimized: false,
            isActive: true,
            isPinned: false,
            isAudible: false,
            isPrivate: false,
            capabilities: .browserScript,
            riskLevel: .low
        )
        let section = WindowHubAppSection(
            id: "42",
            pid: 42,
            bundleIdentifier: "com.google.Chrome",
            appName: "Chrome",
            windowGroups: [
                WindowHubWindowGroup(
                    id: "42-7",
                    windowID: 7,
                    title: "Example",
                    isMinimized: false,
                    isActive: true,
                    isHeavy: false,
                    visibleTargets: [target],
                    hiddenTabCount: 0,
                    capabilities: .browserScript
                ),
            ],
            isBackgroundOnly: false
        )
        let cached = WindowHubCachedSnapshot(
            capturedAt: Date(),
            currentTargetID: target.id,
            sections: [section],
            flatTargets: [windowTarget, target]
        )

        WindowHubSnapshotCache.save(cached)
        let loaded = WindowHubSnapshotCache.load()

        XCTAssertEqual(loaded?.flatTargets.map(\.id), [target.id])
    }

    func testFlatTargetsOmitsWindowRowWhenTabsPresent() {
        let tab = WindowHubTarget(
            id: .tab(pid: 1, windowID: 10, tabKey: "a"),
            kind: .tab,
            pid: 1,
            bundleIdentifier: "com.google.Chrome",
            appName: "Chrome",
            windowID: 10,
            windowTitle: "Window",
            tabTitle: "Docs",
            domain: "example.com",
            isMinimized: false,
            isActive: true,
            isPinned: false,
            isAudible: false,
            isPrivate: false,
            capabilities: .browserAX,
            riskLevel: .medium
        )
        let section = WindowHubAppSection(
            id: "1",
            pid: 1,
            bundleIdentifier: "com.google.Chrome",
            appName: "Chrome",
            windowGroups: [
                WindowHubWindowGroup(
                    id: "1-10",
                    windowID: 10,
                    title: "Docs",
                    isMinimized: false,
                    isActive: true,
                    isHeavy: false,
                    visibleTargets: [tab],
                    hiddenTabCount: 0,
                    capabilities: .browserAX
                ),
            ],
            isBackgroundOnly: false
        )

        let flatTargets = WindowHubSectionMerger.flatTargets(from: [section])
        XCTAssertEqual(flatTargets.count, 1)
        XCTAssertEqual(flatTargets.first?.kind, .tab)
    }
}

final class WindowHubSectionMergerTests: XCTestCase {
    func testUpsertReplacesByPID() {
        let first = makeSection(pid: 1, name: "Alpha")
        let updated = makeSection(pid: 1, name: "Alpha Updated")
        var sections = [first]
        WindowHubSectionMerger.upsert(updated, into: &sections)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].appName, "Alpha Updated")
    }

    func testSortedPutsFrontAppFirst() {
        let a = makeSection(pid: 1, name: "Alpha")
        let b = makeSection(pid: 2, name: "Beta")
        let sorted = WindowHubSectionMerger.sorted([a, b], frontPID: 2)
        XCTAssertEqual(sorted.map(\.pid), [2, 1])
    }

    private func makeSection(pid: pid_t, name: String) -> WindowHubAppSection {
        WindowHubAppSection(
            id: "\(pid)",
            pid: pid,
            bundleIdentifier: nil,
            appName: name,
            windowGroups: [],
            isBackgroundOnly: true
        )
    }
}

final class WindowHubBrowserMatchingTests: XCTestCase {
    func testActiveTabTitleMatch() {
        let window = BrowserAppleScriptTabReader.WindowPayload(
            index: 1,
            name: "Other",
            tabs: [
                BrowserAppleScriptTabReader.TabPayload(
                    index: 1,
                    title: "Stargate-Cerebro",
                    url: "https://example.com",
                    isActive: true
                ),
            ]
        )
        XCTAssertTrue(
            BrowserAppleScriptTabCache.activeTabTitleMatch("Stargate-Cerebro - Google Chrome", window: window)
        )
    }

    func testNamesMatchRejectsPlaceholderWindow() {
        XCTAssertFalse(BrowserAppleScriptTabCache.namesMatch("Window", "Chrome"))
    }

    func testAssignAllWindowsMatchesByTabCount() {
        let pid: pid_t = 99
        BrowserAppleScriptTabCache.beginSnapshot(pid: pid, bundleIdentifier: "com.google.Chrome", forceRefresh: true)

        lockAndSeedWindows(pid: pid, windows: [
            BrowserAppleScriptTabReader.WindowPayload(
                index: 1,
                name: "Unrelated",
                tabs: [
                    BrowserAppleScriptTabReader.TabPayload(index: 1, title: "One", url: nil, isActive: true),
                    BrowserAppleScriptTabReader.TabPayload(index: 2, title: "Two", url: nil, isActive: false),
                ]
            ),
            BrowserAppleScriptTabReader.WindowPayload(
                index: 2,
                name: "Other",
                tabs: [
                    BrowserAppleScriptTabReader.TabPayload(index: 1, title: "Only", url: nil, isActive: true),
                ]
            ),
        ])

        let assignments = BrowserAppleScriptTabCache.assignAllWindows(
            pid: pid,
            probes: [
                BrowserAppleScriptTabCache.WindowProbe(
                    windowID: 10,
                    title: "Window",
                    usesAppElement: false,
                    tabCount: 2
                ),
                BrowserAppleScriptTabCache.WindowProbe(
                    windowID: 11,
                    title: "Window",
                    usesAppElement: false,
                    tabCount: 1
                ),
            ]
        )

        XCTAssertEqual(assignments[10], 1)
        XCTAssertEqual(assignments[11], 2)
        BrowserAppleScriptTabCache.evict(pid: pid)
    }

    private func lockAndSeedWindows(
        pid: pid_t,
        windows: [BrowserAppleScriptTabReader.WindowPayload]
    ) {
        // Test-only helper: seed JXA cache without running osascript.
        BrowserAppleScriptTabCache._testSeedWindows(pid: pid, windows: windows)
    }
}
