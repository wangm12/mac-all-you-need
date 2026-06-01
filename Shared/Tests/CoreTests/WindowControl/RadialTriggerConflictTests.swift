import Core
import XCTest

final class RadialTriggerConflictTests: XCTestCase {
    func testDetectsDragModifierConflict() {
        var settings = WindowControlSettings.default
        settings.radialTriggerModifier = .option
        settings.dragModifier = .option
        let conflicts = RadialTriggerConflict.conflicts(in: settings)
        XCTAssertEqual(
            conflicts.map(\.featureName),
            ["Window Grab", "Edge Snap", "Double-Click Layout"]
        )
    }
}
