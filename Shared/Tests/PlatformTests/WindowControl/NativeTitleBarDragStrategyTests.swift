import CoreGraphics
@testable import Platform
import XCTest

final class NativeTitleBarDragStrategyTests: XCTestCase {
    func testStartsOnlyWithValidTargetAndAccessibilityTrust() {
        let window = FakeDragWindow(frame: CGRect(x: 20, y: 40, width: 800, height: 600))
        let strategy = NativeTitleBarDragStrategy()

        XCTAssertEqual(
            strategy.handle(.mouseDown(at: CGPoint(x: 100, y: 100), axTrusted: false), target: window),
            .passThrough
        )
        XCTAssertFalse(strategy.isActive)

        XCTAssertEqual(
            strategy.handle(
                .mouseDown(at: CGPoint(x: 100, y: 100), axTrusted: true),
                target: FakeDragWindow(
                    frame: CGRect(x: 20, y: 40, width: 800, height: 600),
                    isSupportedForWindowControl: false
                )
            ),
            .passThrough
        )
        XCTAssertFalse(strategy.isActive)
    }

    func testFirstDragRewritesToTitleBarMouseDownAfterMovementThreshold() {
        let window = FakeDragWindow(frame: CGRect(x: 20, y: 40, width: 800, height: 600))
        let strategy = NativeTitleBarDragStrategy(
            configuration: NativeWindowDragConfiguration(titleBarYOffset: 10, movementThreshold: 4)
        )

        XCTAssertEqual(
            strategy.handle(.mouseDown(at: CGPoint(x: 100, y: 100), axTrusted: true), target: window),
            .suppress
        )
        XCTAssertEqual(
            strategy.handle(.mouseDragged(to: CGPoint(x: 102, y: 102), axTrusted: true)),
            .suppress
        )
        XCTAssertFalse(strategy.didDrag)

        XCTAssertEqual(
            strategy.handle(.mouseDragged(to: CGPoint(x: 116, y: 112), axTrusted: true)),
            .rewrite(type: .mouseDown, location: CGPoint(x: 100, y: 50))
        )
        XCTAssertTrue(strategy.didDrag)
    }

    func testLaterDragAndMouseUpPreserveCursorRelativeMovementAndClearState() {
        let window = FakeDragWindow(frame: CGRect(x: 20, y: 40, width: 800, height: 600))
        let strategy = NativeTitleBarDragStrategy(
            configuration: NativeWindowDragConfiguration(titleBarYOffset: 10, movementThreshold: 4)
        )

        _ = strategy.handle(.mouseDown(at: CGPoint(x: 100, y: 100), axTrusted: true), target: window)
        _ = strategy.handle(.mouseDragged(to: CGPoint(x: 116, y: 112), axTrusted: true))

        XCTAssertEqual(
            strategy.handle(.mouseDragged(to: CGPoint(x: 140, y: 132), axTrusted: true)),
            .rewrite(type: .mouseDragged, location: CGPoint(x: 140, y: 82))
        )
        XCTAssertEqual(
            strategy.handle(.mouseUp(at: CGPoint(x: 150, y: 142), axTrusted: true)),
            .rewrite(type: .mouseUp, location: CGPoint(x: 150, y: 92))
        )
        XCTAssertFalse(strategy.isActive)
        XCTAssertFalse(strategy.didDrag)
    }

    func testClickWithoutMovementReplaysOriginalClickAndClearsState() {
        let window = FakeDragWindow(frame: CGRect(x: 20, y: 40, width: 800, height: 600))
        let strategy = NativeTitleBarDragStrategy()

        XCTAssertEqual(
            strategy.handle(.mouseDown(at: CGPoint(x: 100, y: 100), axTrusted: true), target: window),
            .suppress
        )
        XCTAssertEqual(
            strategy.handle(.mouseUp(at: CGPoint(x: 101, y: 101), axTrusted: true)),
            .replayClick(down: CGPoint(x: 100, y: 100), up: CGPoint(x: 101, y: 101))
        )
        XCTAssertFalse(strategy.isActive)
        XCTAssertFalse(strategy.didDrag)
    }

    func testLosingAccessibilityTrustCancelsDragAndPassesSubsequentEventsThrough() {
        let window = FakeDragWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let strategy = NativeTitleBarDragStrategy()

        _ = strategy.handle(.mouseDown(at: CGPoint(x: 100, y: 100), axTrusted: true), target: window)
        XCTAssertEqual(strategy.handle(.mouseDragged(to: CGPoint(x: 150, y: 150), axTrusted: false)), .passThrough)
        XCTAssertFalse(strategy.isActive)
        XCTAssertEqual(strategy.handle(.mouseDragged(to: CGPoint(x: 200, y: 200), axTrusted: true)), .passThrough)
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
        return true
    }

    func setSize(_ size: CGSize) -> Bool {
        frame.size = size
        return true
    }

    func snapshot() -> WindowSnapshot {
        WindowSnapshot(
            frame: frame,
            isResizable: isResizable,
            isMovable: isMovable,
            isSupportedForWindowControl: isSupportedForWindowControl,
            enhancedUserInterfaceEnabled: enhancedUserInterfaceEnabled
        )
    }
}
