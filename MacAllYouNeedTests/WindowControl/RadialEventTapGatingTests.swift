import CoreGraphics
@testable import MacAllYouNeed
import XCTest

@MainActor
final class RadialEventTapGatingTests: XCTestCase {
    private let defaultTrigger: WindowGestureModifier = [.control, .option]

    func testRadialKeysNotInMaskWhenDisabled() {
        let tap = WindowControlEventTap()
        let withoutRadial = tap.eventMask(includeRadialKeys: false)
        let flagsChangedBit = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let mouseMovedBit = CGEventMask(1 << CGEventType.mouseMoved.rawValue)
        XCTAssertEqual(withoutRadial & flagsChangedBit, 0)
        XCTAssertEqual(withoutRadial & mouseMovedBit, 0)
    }

    func testRadialKeysInMaskWhenEnabled() {
        let tap = WindowControlEventTap()
        let withRadial = tap.eventMask(includeRadialKeys: true)
        let flagsChangedBit = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let mouseMovedBit = CGEventMask(1 << CGEventType.mouseMoved.rawValue)
        XCTAssertNotEqual(withRadial & flagsChangedBit, 0)
        XCTAssertNotEqual(withRadial & mouseMovedBit, 0)
    }

    func testTriggerHeldOpensRadial() {
        let flags: CGEventFlags = [.maskControl, .maskAlternate]
        let phase = WindowControlEventTap.radialPhase(
            active: false,
            type: .flagsChanged,
            flags: flags,
            location: CGPoint(x: 10, y: 20),
            triggerModifier: defaultTrigger
        )
        XCTAssertEqual(phase, .open(center: CGPoint(x: 10, y: 20)))
    }

    func testReleaseCommitsRadial() {
        let phase = WindowControlEventTap.radialPhase(
            active: true,
            type: .flagsChanged,
            flags: [],
            location: .zero,
            triggerModifier: defaultTrigger
        )
        XCTAssertEqual(phase, .commit)
    }

    func testMouseMovedUpdatesWhileActive() {
        let phase = WindowControlEventTap.radialPhase(
            active: true,
            type: .mouseMoved,
            flags: [.maskControl, .maskAlternate],
            location: CGPoint(x: 5, y: 5),
            triggerModifier: defaultTrigger
        )
        XCTAssertEqual(phase, .update(cursor: CGPoint(x: 5, y: 5)))
    }

    func testExtraModifierDoesNotArmRadial() {
        // Control+Option+Command should NOT arm the radial menu (exact match).
        let phase = WindowControlEventTap.radialPhase(
            active: false,
            type: .flagsChanged,
            flags: [.maskControl, .maskAlternate, .maskCommand],
            location: .zero,
            triggerModifier: defaultTrigger
        )
        XCTAssertNil(phase)
    }
}
