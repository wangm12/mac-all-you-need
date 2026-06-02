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
        // CG coordinates: origin top-left, Y increases downward.
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
        XCTAssertEqual(zones[0].rect.minX, 1920)
        XCTAssertEqual(zones[0].rect.maxX, 3840)
        XCTAssertEqual(zones[0].rect.maxY, 1080)
        XCTAssertEqual(zones[0].rect.height, 7)
        XCTAssertEqual(zones[0].nudgeVector, CGVector(dx: 0, dy: -7))
    }

    func testStackedScreensBottomDockNoMenuBarZone() {
        let frames = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 0, y: 1080, width: 1920, height: 1080),
        ]
        let zones = DockLockerGeometry.calculateTriggerZones(
            screenFrames: frames,
            lockedScreenIndex: 1,
            dockEdge: .bottom
        )
        XCTAssertTrue(zones.isEmpty)
    }
}
