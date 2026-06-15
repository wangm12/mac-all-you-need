@testable import Core
import CoreGraphics
import XCTest

/// Snapshots pre-refactor `WindowGeometryCalculator` output so the factory must stay byte-identical.
final class WindowCalculationGoldenFrameTests: XCTestCase {
    private let calculator = WindowGeometryCalculator()

    private let standardVisible = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let offsetVisible = CGRect(x: 100, y: 50, width: 1200, height: 800)
    private let windowSize = CGSize(width: 800, height: 500)

    func testGoldenFramesOnStandardVisibleFrame() {
        assertGolden(.leftHalf, visible: standardVisible, expected: CGRect(x: 0, y: 0, width: 720, height: 900))
        assertGolden(.rightHalf, visible: standardVisible, expected: CGRect(x: 720, y: 0, width: 720, height: 900))
        assertGolden(.topHalf, visible: standardVisible, expected: CGRect(x: 0, y: 0, width: 1440, height: 450))
        assertGolden(.bottomHalf, visible: standardVisible, expected: CGRect(x: 0, y: 450, width: 1440, height: 450))
        assertGolden(.topLeft, visible: standardVisible, expected: CGRect(x: 0, y: 0, width: 720, height: 450))
        assertGolden(.topRight, visible: standardVisible, expected: CGRect(x: 720, y: 0, width: 720, height: 450))
        assertGolden(.bottomLeft, visible: standardVisible, expected: CGRect(x: 0, y: 450, width: 720, height: 450))
        assertGolden(.bottomRight, visible: standardVisible, expected: CGRect(x: 720, y: 450, width: 720, height: 450))
        assertGolden(.maximize, visible: standardVisible, expected: standardVisible)
        assertGolden(
            .almostMaximize,
            visible: standardVisible,
            expected: CGRect(x: 72, y: 45, width: 1296, height: 810)
        )
        assertGolden(
            .center,
            visible: standardVisible,
            currentSize: windowSize,
            expected: CGRect(x: 320, y: 200, width: 800, height: 500)
        )
    }

    func testGoldenFramesOnOffsetVisibleFrame() {
        assertGolden(.topHalf, visible: offsetVisible, expected: CGRect(x: 100, y: 50, width: 1200, height: 400))
        assertGolden(.bottomHalf, visible: offsetVisible, expected: CGRect(x: 100, y: 450, width: 1200, height: 400))
        assertGolden(.topLeft, visible: offsetVisible, expected: CGRect(x: 100, y: 50, width: 600, height: 400))
        assertGolden(.bottomRight, visible: offsetVisible, expected: CGRect(x: 700, y: 450, width: 600, height: 400))
    }

    func testGoldenDisplayMoveFrames() {
        let source = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let target = CGRect(x: 1000, y: 100, width: 2000, height: 1000)
        let current = CGRect(x: 250, y: 200, width: 500, height: 400)

        XCTAssertEqual(
            calculator.rectForMovingDisplay(
                currentFrame: current,
                sourceVisibleFrame: source,
                targetVisibleFrame: target
            ),
            CGRect(x: 1250, y: 300, width: 500, height: 400)
        )

        let smallTarget = CGRect(x: 0, y: 0, width: 400, height: 300)
        let largeCurrent = CGRect(x: 800, y: 800, width: 500, height: 400)
        XCTAssertEqual(
            calculator.rectForMovingDisplay(
                currentFrame: largeCurrent,
                sourceVisibleFrame: source,
                targetVisibleFrame: smallTarget
            ),
            CGRect(x: 0, y: 0, width: 400, height: 300)
        )
    }

    func testUnsupportedActionsReturnNil() {
        for action in [WindowAction.restore, .nextDisplay, .previousDisplay, .nextSpace, .previousSpace] {
            XCTAssertNil(calculator.rect(for: action, visibleFrame: standardVisible))
        }
        XCTAssertNil(calculator.rect(for: .center, visibleFrame: standardVisible, currentSize: nil))
    }

    private func assertGolden(
        _ action: WindowAction,
        visible: CGRect,
        currentSize: CGSize? = nil,
        expected: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actual = calculator.rect(for: action, visibleFrame: visible, currentSize: currentSize)
        XCTAssertEqual(actual, expected, "golden mismatch for \(action)", file: file, line: line)
    }
}
