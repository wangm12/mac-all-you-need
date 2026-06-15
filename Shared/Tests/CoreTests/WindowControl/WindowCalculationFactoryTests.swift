@testable import Core
import CoreGraphics
import XCTest

final class WindowCalculationFactoryTests: XCTestCase {
    private let calculator = WindowGeometryCalculator()

    private let standardVisible = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testFactoryMatchesCalculatorForEveryLayoutAction() {
        let layoutActions: [WindowAction] = [
            .leftHalf, .rightHalf, .topHalf, .bottomHalf,
            .topLeft, .topRight, .bottomLeft, .bottomRight,
            .maximize, .almostMaximize, .center
        ]
        let sizes: [CGSize?] = [nil, CGSize(width: 800, height: 500)]
        let frames = [standardVisible, CGRect(x: 100, y: 50, width: 1200, height: 800)]

        for action in layoutActions {
            for visible in frames {
                for size in sizes {
                    if action == .center, size == nil { continue }
                    let expected = calculator.rect(for: action, visibleFrame: visible, currentSize: size)
                    let actual = WindowCalculationFactory.rect(
                        for: action,
                        visibleFrame: visible,
                        currentSize: size
                    )
                    XCTAssertEqual(actual, expected, "factory mismatch for \(action)")
                }
            }
        }
    }

    func testFactoryMatchesCalculatorForDisplayMoves() {
        let source = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let target = CGRect(x: 1000, y: 100, width: 2000, height: 1000)
        let current = CGRect(x: 250, y: 200, width: 500, height: 400)

        let expected = calculator.rectForMovingDisplay(
            currentFrame: current,
            sourceVisibleFrame: source,
            targetVisibleFrame: target
        )
        let actual = WindowCalculationFactory.rectForMovingDisplay(
            currentFrame: current,
            sourceVisibleFrame: source,
            targetVisibleFrame: target
        )
        XCTAssertEqual(actual, expected)
    }

    func testFactoryReturnsNilForUnsupportedActions() {
        for action in [WindowAction.restore, .nextSpace, .previousSpace] {
            XCTAssertNil(WindowCalculationFactory.rect(for: action, visibleFrame: standardVisible))
        }
    }

    func testFactoryDispatchesSingletonCalculations() {
        XCTAssertTrue(WindowCalculationFactory.calculation(for: .leftHalf) is LeftHalfCalculation)
        XCTAssertTrue(WindowCalculationFactory.calculation(for: .nextDisplay) is TranslateToDisplayCalculation)
        XCTAssertNil(WindowCalculationFactory.calculation(for: .restore))
    }
}
