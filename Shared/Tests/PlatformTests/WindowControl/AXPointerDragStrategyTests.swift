@testable import Platform
import XCTest

final class AXPointerDragStrategyTests: XCTestCase {
    func testMovesWindowWithAXPositionDelta() {
        let target = MovableTarget(frame: CGRect(x: 100, y: 200, width: 800, height: 600))
        let strategy = AXPointerDragStrategy(configuration: NativeWindowDragConfiguration(movementThreshold: 2))

        XCTAssertEqual(strategy.handle(.mouseDown(at: CGPoint(x: 150, y: 250), axTrusted: true), target: target), .suppress)
        XCTAssertEqual(
            strategy.handle(.mouseDragged(to: CGPoint(x: 170, y: 270), axTrusted: true), target: target),
            .suppress
        )
        XCTAssertTrue(strategy.didDrag)
        XCTAssertEqual(target.movedOrigin, CGPoint(x: 120, y: 220))
    }
}

private final class MovableTarget: WindowMovableElement {
    var frame: CGRect
    private(set) var movedOrigin: CGPoint?

    init(frame: CGRect) {
        self.frame = frame
    }

    let isResizable = true
    let isMovable = true
    let isSupportedForWindowControl = true
    let enhancedUserInterfaceEnabled: Bool? = nil

    func setEnhancedUserInterfaceEnabled(_: Bool) -> Bool { true }

    func setPosition(_ position: CGPoint) -> Bool {
        movedOrigin = position
        frame.origin = position
        return true
    }

    func setSize(_: CGSize) -> Bool { true }
}
