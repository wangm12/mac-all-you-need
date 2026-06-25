import XCTest
@testable import MacAllYouNeed

final class WindowHubActionPlannerTests: XCTestCase {
    func testHighRiskTargetAlwaysRequiresConfirmation() {
        let target = WindowHubTarget(
            id: .tab(pid: 1, windowID: 2, tabKey: "a"),
            kind: .tab,
            pid: 1,
            bundleIdentifier: "com.google.Chrome",
            appName: "Chrome",
            windowID: 2,
            windowTitle: "Window",
            tabTitle: "Private",
            domain: nil,
            isMinimized: false,
            isActive: true,
            isPinned: false,
            isAudible: false,
            isPrivate: true,
            capabilities: .browserAX,
            riskLevel: .high
        )
        let plan = WindowHubActionPlanner.plan(action: .closeTab, target: target, settings: WindowHubSettings(skipLowRiskConfirmations: true))
        XCTAssertTrue(plan.requiresConfirmation)
    }
}
