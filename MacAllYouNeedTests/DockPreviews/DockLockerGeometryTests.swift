import CoreGraphics
@testable import MacAllYouNeed
import XCTest

final class DockLockerGeometryTests: XCTestCase {
    func testMergeAdjacentIntervals() {
        let merged = DockEdgeInterval.merge([
            DockEdgeInterval(start: 0, end: 100),
            DockEdgeInterval(start: 100, end: 200),
        ])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0], DockEdgeInterval(start: 0, end: 200))
    }

    func testTwoScreensBottomDockLockedLeft() {
        let frames = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 1920, y: 0, width: 1920, height: 1080),
        ]
        let zones = DockLockerGeometry.calculateTriggerZones(
            screenFrames: frames,
            lockedScreenIndex: 0,
            dockEdge: .bottom
        )
        XCTAssertEqual(zones.count, 1)
        XCTAssertEqual(zones[0].nudgeVector, CGVector(dx: 0, dy: -7))
    }
}
