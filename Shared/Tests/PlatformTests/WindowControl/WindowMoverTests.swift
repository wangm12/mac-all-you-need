import CoreGraphics
@testable import Platform
import XCTest

final class WindowMoverTests: XCTestCase {
    func testResizableWindowWritesSizePositionSize() {
        let element = FakeWindowElement(frame: CGRect(x: 100, y: 100, width: 800, height: 600))
        let mover = WindowMover(screenDetector: fixedDetector())

        let result = mover.move(element, action: .leftHalf)

        XCTAssertEqual(result.proposedFrame, CGRect(x: 0, y: 0, width: 720, height: 900))
        XCTAssertEqual(result.resultingFrame, CGRect(x: 0, y: 0, width: 720, height: 900))
        XCTAssertEqual(element.operations, [
            .size(CGSize(width: 720, height: 900)),
            .position(CGPoint(x: 0, y: 0)),
            .size(CGSize(width: 720, height: 900))
        ])
    }

    func testFixedSizeWindowDoesNotResizeForResizeAction() {
        let element = FakeWindowElement(
            frame: CGRect(x: 100, y: 100, width: 800, height: 600),
            isResizable: false
        )
        let mover = WindowMover(screenDetector: fixedDetector())

        let result = mover.move(element, action: .leftHalf)

        XCTAssertEqual(result.status, .fixedSizeWindow)
        XCTAssertEqual(element.operations, [])
        XCTAssertEqual(element.frame, CGRect(x: 100, y: 100, width: 800, height: 600))
    }

    func testFixedSizeWindowCanMoveWhenSizeIsUnchanged() {
        let element = FakeWindowElement(
            frame: CGRect(x: 100, y: 100, width: 800, height: 600),
            isResizable: false
        )
        let mover = WindowMover(screenDetector: fixedDetector())

        let result = mover.move(element, action: .center)

        XCTAssertEqual(result.status, .moved)
        XCTAssertEqual(result.proposedFrame, CGRect(x: 320, y: 150, width: 800, height: 600))
        XCTAssertEqual(element.operations, [
            .position(CGPoint(x: 320, y: 150))
        ])
    }

    func testEnhancedUserInterfaceIsDisabledAndRestoredAroundMovement() {
        let element = FakeWindowElement(
            frame: CGRect(x: 100, y: 100, width: 800, height: 600),
            enhancedUserInterfaceEnabled: true
        )
        let mover = WindowMover(screenDetector: fixedDetector())

        _ = mover.move(element, action: .rightHalf)

        XCTAssertEqual(element.operations, [
            .enhancedUserInterface(false),
            .size(CGSize(width: 720, height: 900)),
            .position(CGPoint(x: 720, y: 0)),
            .size(CGSize(width: 720, height: 900)),
            .enhancedUserInterface(true)
        ])
    }

    func testMovementContinuesAllThreeWritesEvenWhenPositionReturnsFalse() {
        // The new WindowMover ignores individual AX return values (they're
        // unreliable for size/position) and determines success from the
        // resulting frame. We still expect all three writes to run.
        let element = FakeWindowElement(
            frame: CGRect(x: 100, y: 100, width: 800, height: 600),
            setPositionSucceeds: false
        )
        let mover = WindowMover(screenDetector: fixedDetector())

        let result = mover.move(element, action: .leftHalf)

        XCTAssertEqual(result.status, .moved)
        XCTAssertEqual(element.operations, [
            .size(CGSize(width: 720, height: 900)),
            .position(CGPoint(x: 0, y: 0)),
            .size(CGSize(width: 720, height: 900))
        ])
    }

    func testEnhancedUserInterfaceRestoreFailureReturnsWriteFailed() {
        let element = FakeWindowElement(
            frame: CGRect(x: 100, y: 100, width: 800, height: 600),
            enhancedUserInterfaceEnabled: true,
            setEnhancedUserInterfaceSucceeds: [true, false]
        )
        let mover = WindowMover(screenDetector: fixedDetector())

        let result = mover.move(element, action: .rightHalf)

        XCTAssertEqual(result.status, .writeFailed)
        XCTAssertEqual(element.operations, [
            .enhancedUserInterface(false),
            .size(CGSize(width: 720, height: 900)),
            .position(CGPoint(x: 720, y: 0)),
            .size(CGSize(width: 720, height: 900)),
            .enhancedUserInterface(true)
        ])
    }

    func testKeyboardActionUsesWindowCurrentDisplayVisibleFrame() {
        let left = WindowControlScreen(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )
        let right = WindowControlScreen(
            id: 2,
            frame: CGRect(x: 1440, y: 0, width: 1280, height: 800),
            visibleFrame: CGRect(x: 1440, y: 20, width: 1280, height: 760)
        )
        let element = FakeWindowElement(frame: CGRect(x: 1500, y: 100, width: 600, height: 400))
        let mover = WindowMover(screenDetector: WindowScreenDetector(screens: [left, right]))

        let result = mover.move(element, action: .maximize)

        XCTAssertEqual(result.proposedFrame, right.visibleFrame)
        XCTAssertEqual(element.frame, right.visibleFrame)
    }

    func testNextDisplayPreservesSizeAndTranslatesPosition() {
        let left = WindowControlScreen(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )
        let right = WindowControlScreen(
            id: 2,
            frame: CGRect(x: 1000, y: 0, width: 2000, height: 1000),
            visibleFrame: CGRect(x: 1000, y: 100, width: 2000, height: 900)
        )
        let element = FakeWindowElement(frame: CGRect(x: 100, y: 200, width: 500, height: 400))
        let mover = WindowMover(screenDetector: WindowScreenDetector(screens: [left, right]))

        let result = mover.move(element, action: .nextDisplay)

        XCTAssertEqual(result.proposedFrame, CGRect(x: 1100, y: 300, width: 500, height: 400))
        XCTAssertEqual(element.frame, CGRect(x: 1100, y: 300, width: 500, height: 400))
    }

    func testFixedSizeNextDisplayPreservesCurrentSizeAndMovesOnlyPosition() {
        let left = WindowControlScreen(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )
        let right = WindowControlScreen(
            id: 2,
            frame: CGRect(x: 1000, y: 0, width: 2000, height: 1000),
            visibleFrame: CGRect(x: 1000, y: 100, width: 2000, height: 900)
        )
        let element = FakeWindowElement(
            frame: CGRect(x: 100, y: 200, width: 500, height: 400),
            isResizable: false
        )
        let mover = WindowMover(screenDetector: WindowScreenDetector(screens: [left, right]))

        let result = mover.move(element, action: .nextDisplay)

        XCTAssertEqual(result.status, .moved)
        XCTAssertEqual(result.proposedFrame, CGRect(x: 1100, y: 300, width: 500, height: 400))
        XCTAssertEqual(element.operations, [
            .position(CGPoint(x: 1100, y: 300))
        ])
    }

    func testFixedSizePreviousDisplayPreservesCurrentSizeAndMovesOnlyPosition() {
        let left = WindowControlScreen(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )
        let right = WindowControlScreen(
            id: 2,
            frame: CGRect(x: 1000, y: 0, width: 2000, height: 1000),
            visibleFrame: CGRect(x: 1000, y: 100, width: 2000, height: 900)
        )
        let element = FakeWindowElement(
            frame: CGRect(x: 1200, y: 325, width: 500, height: 400),
            isResizable: false
        )
        let mover = WindowMover(screenDetector: WindowScreenDetector(screens: [left, right]))

        let result = mover.move(element, action: .previousDisplay)

        XCTAssertEqual(result.status, .moved)
        XCTAssertEqual(result.proposedFrame, CGRect(x: 200, y: 225, width: 500, height: 400))
        XCTAssertEqual(element.operations, [
            .position(CGPoint(x: 200, y: 225))
        ])
    }

    func testNextDisplayOnSingleDisplayReturnsNoTargetFrame() {
        let element = FakeWindowElement(frame: CGRect(x: 100, y: 100, width: 800, height: 600))
        let mover = WindowMover(screenDetector: fixedDetector())

        let result = mover.move(element, action: .nextDisplay)

        XCTAssertEqual(result.status, .noTargetFrame)
        XCTAssertNil(result.proposedFrame)
        XCTAssertEqual(element.operations, [])
    }

    func testPreviousDisplayOnSingleDisplayReturnsNoTargetFrame() {
        let element = FakeWindowElement(frame: CGRect(x: 100, y: 100, width: 800, height: 600))
        let mover = WindowMover(screenDetector: fixedDetector())

        let result = mover.move(element, action: .previousDisplay)

        XCTAssertEqual(result.status, .noTargetFrame)
        XCTAssertNil(result.proposedFrame)
        XCTAssertEqual(element.operations, [])
    }

    func testRepeatedRightHalfMovesToNextDisplayLeftHalfLikeRectangle() {
        let left = WindowControlScreen(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )
        let right = WindowControlScreen(
            id: 2,
            frame: CGRect(x: 1000, y: 0, width: 1000, height: 800),
            visibleFrame: CGRect(x: 1000, y: 0, width: 1000, height: 800)
        )
        let repeatedFrame = CGRect(x: 500, y: 0, width: 500, height: 800)
        let previous = WindowMovementResult(
            action: .rightHalf,
            status: .moved,
            originalFrame: CGRect(x: 100, y: 100, width: 600, height: 400),
            proposedFrame: repeatedFrame,
            resultingFrame: repeatedFrame
        )
        let element = FakeWindowElement(frame: repeatedFrame)
        let mover = WindowMover(screenDetector: WindowScreenDetector(screens: [left, right]))

        let result = mover.move(element, action: .rightHalf, previousResult: previous)

        XCTAssertEqual(result.action, .leftHalf)
        XCTAssertEqual(result.proposedFrame, CGRect(x: 1000, y: 0, width: 500, height: 800))
        XCTAssertEqual(element.frame, CGRect(x: 1000, y: 0, width: 500, height: 800))
    }

    func testRepeatedTopHalfMovesToDisplayAboveBottomHalf() {
        let lower = WindowControlScreen(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )
        let upper = WindowControlScreen(
            id: 2,
            frame: CGRect(x: 0, y: -900, width: 1000, height: 900),
            visibleFrame: CGRect(x: 0, y: -900, width: 1000, height: 900)
        )
        let repeatedFrame = CGRect(x: 0, y: 0, width: 1000, height: 400)
        let previous = WindowMovementResult(
            action: .topHalf,
            status: .moved,
            originalFrame: CGRect(x: 100, y: 100, width: 600, height: 400),
            proposedFrame: repeatedFrame,
            resultingFrame: repeatedFrame
        )
        let element = FakeWindowElement(frame: repeatedFrame)
        let mover = WindowMover(screenDetector: WindowScreenDetector(screens: [lower, upper]))

        let result = mover.move(element, action: .topHalf, previousResult: previous)

        XCTAssertEqual(result.action, .bottomHalf)
        XCTAssertEqual(result.proposedFrame, CGRect(x: 0, y: -450, width: 1000, height: 450))
        XCTAssertEqual(element.frame, CGRect(x: 0, y: -450, width: 1000, height: 450))
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

private final class FakeWindowElement: WindowMovableElement {
    enum Operation: Equatable {
        case enhancedUserInterface(Bool)
        case position(CGPoint)
        case size(CGSize)
    }

    var frame: CGRect
    let isResizable: Bool
    let isMovable = true
    let isSupportedForWindowControl = true
    var enhancedUserInterfaceEnabled: Bool?
    private var setEnhancedUserInterfaceSucceeds: [Bool]
    private let setPositionSucceeds: Bool
    private let setSizeSucceeds: Bool
    private(set) var operations: [Operation] = []

    init(
        frame: CGRect,
        isResizable: Bool = true,
        enhancedUserInterfaceEnabled: Bool? = nil,
        setEnhancedUserInterfaceSucceeds: [Bool] = [true],
        setPositionSucceeds: Bool = true,
        setSizeSucceeds: Bool = true
    ) {
        self.frame = frame
        self.isResizable = isResizable
        self.enhancedUserInterfaceEnabled = enhancedUserInterfaceEnabled
        self.setEnhancedUserInterfaceSucceeds = setEnhancedUserInterfaceSucceeds
        self.setPositionSucceeds = setPositionSucceeds
        self.setSizeSucceeds = setSizeSucceeds
    }

    func setEnhancedUserInterfaceEnabled(_ enabled: Bool) -> Bool {
        enhancedUserInterfaceEnabled = enabled
        operations.append(.enhancedUserInterface(enabled))
        guard !setEnhancedUserInterfaceSucceeds.isEmpty else {
            return true
        }
        return setEnhancedUserInterfaceSucceeds.removeFirst()
    }

    func setPosition(_ position: CGPoint) -> Bool {
        frame.origin = position
        operations.append(.position(position))
        return setPositionSucceeds
    }

    func setSize(_ size: CGSize) -> Bool {
        frame.size = size
        operations.append(.size(size))
        return setSizeSucceeds
    }
}
