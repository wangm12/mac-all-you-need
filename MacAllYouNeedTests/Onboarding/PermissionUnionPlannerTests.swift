@testable import MacAllYouNeed
import FeatureCore
import XCTest

final class PermissionUnionPlannerTests: XCTestCase {
    func testUnionDeduplicatesAccessibilityAcrossFeatures() {
        let clipboard = FeatureDescriptor(
            id: .clipboard,
            displayName: "Clipboard",
            icon: "doc",
            summary: "",
            detailDescription: "",
            requiredPermissions: [.accessibility],
            activator: NoopFeatureActivator()
        )
        let voice = FeatureDescriptor(
            id: .voice,
            displayName: "Voice",
            icon: "mic",
            summary: "",
            detailDescription: "",
            requiredPermissions: [.accessibility, .microphone],
            activator: NoopFeatureActivator()
        )
        let entries = PermissionUnionPlanner.union(for: [clipboard, voice])
        XCTAssertEqual(entries.count, 2)
        let accessibility = entries.first { $0.permission == .accessibility }
        XCTAssertEqual(accessibility?.featureNames.sorted(), ["Clipboard", "Voice"])
    }
}
