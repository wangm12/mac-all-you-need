import CoreGraphics
@testable import Platform
import XCTest

final class NativeTitleBarDragStrategyTests: XCTestCase {
    func testModifierDragMovesWindowOriginByCursorDelta() {
        let window = FakeDragWindow(frame: CGRect(x: 20, y: 40, width: 800, height: 600))
        let strategy = NativeTitleBarDragStrategy()

        XCTAssertEqual(
            strategy.handle(.mouseDown(at: CGPoint(x: 100, y: 100), axTrusted: true), target: window),
            .passThrough
        )
        XCTAssertEqual(
            strategy.handle(.mouseDragged(to: CGPoint(x: 160, y: 135), axTrusted: true)),
            .suppress
        )

        XCTAssertEqual(window.frame.origin, CGPoint(x: 80, y: 75))
        XCTAssertEqual(window.positions, [CGPoint(x: 80, y: 75)])
    }

    func testClickWithoutDragDoesNotMoveWindowOrSwallowClick() {
        let window = FakeDragWindow(frame: CGRect(x: 20, y: 40, width: 800, height: 600))
        let strategy = NativeTitleBarDragStrategy()

        let downDecision = strategy.handle(.mouseDown(at: CGPoint(x: 100, y: 100), axTrusted: true), target: window)
        let upDecision = strategy.handle(.mouseUp(at: CGPoint(x: 100, y: 100), axTrusted: true))

        XCTAssertEqual(downDecision, .passThrough)
        XCTAssertEqual(upDecision, .passThrough)
        XCTAssertEqual(window.frame.origin, CGPoint(x: 20, y: 40))
        XCTAssertEqual(window.positions, [])
    }

    func testMouseUpAfterDragExitsActiveStateAndSubsequentEventsPassThrough() {
        let window = FakeDragWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let strategy = NativeTitleBarDragStrategy()

        _ = strategy.handle(.mouseDown(at: CGPoint(x: 100, y: 100), axTrusted: true), target: window)
        XCTAssertEqual(strategy.handle(.mouseDragged(to: CGPoint(x: 150, y: 150), axTrusted: true)), .suppress)
        XCTAssertEqual(strategy.handle(.mouseUp(at: CGPoint(x: 150, y: 150), axTrusted: true)), .suppress)
        XCTAssertFalse(strategy.isActive)
        XCTAssertEqual(strategy.handle(.mouseDragged(to: CGPoint(x: 200, y: 200), axTrusted: true)), .passThrough)
        XCTAssertEqual(window.positions, [CGPoint(x: 50, y: 50)])
    }

    func testLosingAccessibilityTrustCancelsDragAndPassesSubsequentEventsThrough() {
        let window = FakeDragWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let strategy = NativeTitleBarDragStrategy()

        _ = strategy.handle(.mouseDown(at: CGPoint(x: 100, y: 100), axTrusted: true), target: window)
        XCTAssertEqual(strategy.handle(.mouseDragged(to: CGPoint(x: 150, y: 150), axTrusted: false)), .passThrough)
        XCTAssertFalse(strategy.isActive)
        XCTAssertEqual(strategy.handle(.mouseDragged(to: CGPoint(x: 200, y: 200), axTrusted: true)), .passThrough)
        XCTAssertEqual(window.positions, [])
    }

    func testUnsupportedTargetDoesNotStartGesture() {
        let window = FakeDragWindow(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            isSupportedForWindowControl: false
        )
        let strategy = NativeTitleBarDragStrategy()

        XCTAssertEqual(strategy.handle(.mouseDown(at: CGPoint(x: 100, y: 100), axTrusted: true), target: window), .passThrough)
        XCTAssertEqual(strategy.handle(.mouseDragged(to: CGPoint(x: 150, y: 150), axTrusted: true)), .passThrough)
        XCTAssertFalse(strategy.isActive)
        XCTAssertEqual(window.positions, [])
    }

    func testEnhancedUserInterfaceIsDisabledDuringDragAndRestoredOnMouseUp() {
        let window = FakeDragWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        window.enhancedUserInterfaceEnabled = true
        let strategy = NativeTitleBarDragStrategy()

        _ = strategy.handle(.mouseDown(at: CGPoint(x: 100, y: 100), axTrusted: true), target: window)
        XCTAssertEqual(window.enhancedUserInterfaceEnabled, false)

        _ = strategy.handle(.mouseDragged(to: CGPoint(x: 150, y: 150), axTrusted: true))
        _ = strategy.handle(.mouseUp(at: CGPoint(x: 150, y: 150), axTrusted: true))

        XCTAssertEqual(window.enhancedUserInterfaceEnabled, true)
        XCTAssertEqual(window.enhancedUserInterfaceWrites, [false, true])
    }

    func testTitleBarDragRegionUsesTopOfAXFrame() {
        let frame = CGRect(x: 20, y: 40, width: 800, height: 600)

        XCTAssertTrue(WindowTitleBarDragRegion.contains(CGPoint(x: 100, y: 50), in: frame))
        XCTAssertFalse(WindowTitleBarDragRegion.contains(CGPoint(x: 100, y: 140), in: frame))
        XCTAssertFalse(WindowTitleBarDragRegion.contains(CGPoint(x: 10, y: 50), in: frame))
    }
}

private final class FakeDragWindow: WindowMovableElement {
    var frame: CGRect
    let isResizable = true
    let isMovable = true
    let isSupportedForWindowControl: Bool
    var enhancedUserInterfaceEnabled: Bool?
    private(set) var enhancedUserInterfaceWrites: [Bool] = []
    private(set) var positions: [CGPoint] = []

    init(frame: CGRect, isSupportedForWindowControl: Bool = true, enhancedUserInterfaceEnabled: Bool? = nil) {
        self.frame = frame
        self.isSupportedForWindowControl = isSupportedForWindowControl
        self.enhancedUserInterfaceEnabled = enhancedUserInterfaceEnabled
    }

    func setEnhancedUserInterfaceEnabled(_ enabled: Bool) -> Bool {
        enhancedUserInterfaceEnabled = enabled
        enhancedUserInterfaceWrites.append(enabled)
        return true
    }

    func setPosition(_ position: CGPoint) -> Bool {
        frame.origin = position
        positions.append(position)
        return true
    }

    func setSize(_ size: CGSize) -> Bool {
        frame.size = size
        return true
    }
}
