import CoreGraphics
@testable import Platform
import XCTest

final class WindowCrossDisplayRetryTests: XCTestCase {
    func testCrossDisplayRetryCorrectsHeightClampOnFirstWrite() {
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
        let element = HeightClampingFakeWindowElement(
            frame: CGRect(x: 100, y: 200, width: 500, height: 400),
            clampHeightTo: 300
        )
        let mover = WindowMover(screenDetector: WindowScreenDetector(screens: [left, right]))

        let result = mover.move(element, action: .nextDisplay)

        XCTAssertEqual(result.status, .moved)
        XCTAssertEqual(result.proposedFrame?.size.height, 400)
        XCTAssertEqual(element.totalSizeWrites, 4, "Two clamped size-write pairs plus one corrective pair")
        XCTAssertEqual(element.storedFrame.size.height, 400, accuracy: 0.5)
    }

    func testCrossDisplayAsyncRetryRunsWhenImmediateRetryStillClamped() {
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
        let element = HeightClampingFakeWindowElement(
            frame: CGRect(x: 100, y: 200, width: 500, height: 400),
            clampHeightTo: 300,
            clampedSizeBatchLimit: 2
        )
        let mover = WindowMover(screenDetector: WindowScreenDetector(screens: [left, right]))
        var scheduledRetries = 0
        var writesBeforeAsyncRetry = 0
        mover.crossDisplayRetryScheduler = { work in
            scheduledRetries += 1
            writesBeforeAsyncRetry = element.totalSizeWrites
            work()
        }

        let result = mover.move(element, action: .nextDisplay)

        XCTAssertEqual(result.status, .moved)
        XCTAssertEqual(scheduledRetries, 1)
        XCTAssertEqual(writesBeforeAsyncRetry, 4)
        XCTAssertEqual(element.totalSizeWrites, 6)
        XCTAssertEqual(element.storedFrame.size.height, 400, accuracy: 0.5)
    }

    func testNeedsSizeCorrectionDetectsHeightMismatch() {
        let proposed = CGRect(x: 0, y: 0, width: 500, height: 400)
        let actual = CGRect(x: 0, y: 0, width: 500, height: 300)
        XCTAssertTrue(WindowCrossDisplayRetry.needsSizeCorrection(actual: actual, proposed: proposed))
    }

    func testIsCrossDisplayMoveForNextDisplayAction() {
        let detector = WindowScreenDetector(screens: [
            WindowControlScreen(
                id: 1,
                frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
            )
        ])
        XCTAssertTrue(
            WindowCrossDisplayRetry.isCrossDisplayMove(
                action: .nextDisplay,
                originalFrame: CGRect(x: 100, y: 100, width: 400, height: 300),
                proposedFrame: CGRect(x: 1100, y: 200, width: 400, height: 300),
                screenDetector: detector
            )
        )
    }
}

private final class HeightClampingFakeWindowElement: WindowMovableElement {
    var storedFrame: CGRect
    let isResizable = true
    let isMovable = true
    let isSupportedForWindowControl = true
    var enhancedUserInterfaceEnabled: Bool?
    private let clampHeightTo: CGFloat
    /// Number of size-write pairs (each `applyInstantFrameWrite` issues two) to clamp.
    private let clampedSizeBatchLimit: Int
    private var sizeWriteCount = 0

    var frame: CGRect { storedFrame }
    var totalSizeWrites: Int { sizeWriteCount }

    init(frame: CGRect, clampHeightTo: CGFloat, clampedSizeBatchLimit: Int = 1) {
        storedFrame = frame
        self.clampHeightTo = clampHeightTo
        self.clampedSizeBatchLimit = clampedSizeBatchLimit
    }

    func snapshot() -> WindowSnapshot {
        WindowSnapshot(
            frame: storedFrame,
            isResizable: isResizable,
            isMovable: isMovable,
            isSupportedForWindowControl: isSupportedForWindowControl,
            enhancedUserInterfaceEnabled: enhancedUserInterfaceEnabled
        )
    }

    func setEnhancedUserInterfaceEnabled(_: Bool) -> Bool { true }

    func setPosition(_ position: CGPoint) -> Bool {
        storedFrame.origin = position
        return true
    }

    func setSize(_ size: CGSize) -> Bool {
        sizeWriteCount += 1
        let batch = (sizeWriteCount + 1) / 2
        if batch <= clampedSizeBatchLimit {
            storedFrame.size = CGSize(width: size.width, height: min(size.height, clampHeightTo))
        } else {
            storedFrame.size = size
        }
        return true
    }
}
