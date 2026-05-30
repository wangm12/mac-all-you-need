import Core
import CoreGraphics
@testable import Platform
import XCTest

/// Verifies `WindowMover.proposedFrame` returns the same rect `move` would write
/// for every radial ring action plus the center action — the radial preview must
/// match the eventual placement.
final class RadialProposedFrameParityTests: XCTestCase {
    func testProposedFrameMatchesMoveForRingActions() {
        for action in RadialMenuLayout.ringActions + [RadialMenuLayout.centerAction] {
            let previewElement = makeElement()
            let moveElement = makeElement()
            let previewMover = WindowMover(screenDetector: fixedDetector())
            let moveMover = WindowMover(screenDetector: fixedDetector())

            let proposed = previewMover.proposedFrame(for: action, element: previewElement)
            let moved = moveMover.move(moveElement, action: action)

            XCTAssertEqual(
                proposed,
                moved.proposedFrame,
                "proposed frame should match move() for \(action)"
            )
            XCTAssertNotNil(proposed, "expected a proposed frame for \(action)")
        }
    }

    func testProposedFrameIsNilForUnsupportedWindow() {
        let element = FakeRadialWindowElement(
            frame: CGRect(x: 100, y: 100, width: 800, height: 600),
            isSupported: false
        )
        let mover = WindowMover(screenDetector: fixedDetector())
        XCTAssertNil(mover.proposedFrame(for: .leftHalf, element: element))
    }

    private func makeElement() -> FakeRadialWindowElement {
        FakeRadialWindowElement(frame: CGRect(x: 100, y: 100, width: 800, height: 600))
    }

    private func fixedDetector() -> WindowScreenDetector {
        WindowScreenDetector(screens: [
            WindowControlScreen(
                id: 1,
                frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
            )
        ])
    }
}

private final class FakeRadialWindowElement: WindowMovableElement {
    var frame: CGRect
    let isResizable = true
    let isMovable = true
    let isSupportedForWindowControl: Bool
    var enhancedUserInterfaceEnabled: Bool?

    init(frame: CGRect, isSupported: Bool = true) {
        self.frame = frame
        isSupportedForWindowControl = isSupported
    }

    func setEnhancedUserInterfaceEnabled(_: Bool) -> Bool { true }
    func setPosition(_ position: CGPoint) -> Bool { frame.origin = position; return true }
    func setSize(_ size: CGSize) -> Bool { frame.size = size; return true }
}
