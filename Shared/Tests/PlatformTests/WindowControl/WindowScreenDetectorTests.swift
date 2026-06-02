import CoreGraphics
@testable import Platform
import XCTest

final class WindowScreenDetectorTests: XCTestCase {
    func testChoosesScreenWithLargestWindowIntersection() {
        let detector = WindowScreenDetector(screens: [
            WindowControlScreen(
                id: 1,
                frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
            ),
            WindowControlScreen(
                id: 2,
                frame: CGRect(x: 1000, y: 0, width: 1000, height: 800),
                visibleFrame: CGRect(x: 1000, y: 0, width: 1000, height: 800)
            )
        ])

        let screen = detector.screen(containing: CGRect(x: 900, y: 100, width: 500, height: 400))

        XCTAssertEqual(screen?.id, 2)
    }

    func testFallsBackToNearestScreenWhenFrameDoesNotIntersectAnyScreen() {
        let detector = WindowScreenDetector(screens: [
            WindowControlScreen(
                id: 1,
                frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
            ),
            WindowControlScreen(
                id: 2,
                frame: CGRect(x: 1600, y: 0, width: 1000, height: 800),
                visibleFrame: CGRect(x: 1600, y: 0, width: 1000, height: 800)
            )
        ])

        let screen = detector.screen(containing: CGRect(x: 1300, y: 100, width: 100, height: 100))

        XCTAssertEqual(screen?.id, 2)
    }

    func testNextAndPreviousDisplayWrapInConfiguredOrder() {
        let first = WindowControlScreen(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )
        let second = WindowControlScreen(
            id: 2,
            frame: CGRect(x: 1000, y: 0, width: 1000, height: 800),
            visibleFrame: CGRect(x: 1000, y: 0, width: 1000, height: 800)
        )
        let detector = WindowScreenDetector(screens: [first, second])

        XCTAssertEqual(detector.nextScreen(after: first)?.id, 2)
        XCTAssertEqual(detector.nextScreen(after: second)?.id, 1)
        XCTAssertEqual(detector.previousScreen(before: first)?.id, 2)
        XCTAssertEqual(detector.previousScreen(before: second)?.id, 1)
    }

    func testTraversalOrderMatchesTopToBottomThenLeftToRightDisplays() {
        let lowerRight = WindowControlScreen(
            id: 1,
            frame: CGRect(x: 1000, y: 0, width: 1000, height: 800),
            visibleFrame: CGRect(x: 1000, y: 0, width: 1000, height: 800)
        )
        let upper = WindowControlScreen(
            id: 2,
            frame: CGRect(x: 200, y: -900, width: 1200, height: 900),
            visibleFrame: CGRect(x: 200, y: -900, width: 1200, height: 900)
        )
        let lowerLeft = WindowControlScreen(
            id: 3,
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )

        let ordered = WindowScreenDetector.traversalOrderedScreens([lowerRight, upper, lowerLeft])

        XCTAssertEqual(ordered.map(\.id), [2, 3, 1])
    }

    func testDesktopBoundsUnionsAllDisplays() {
        let left = WindowControlScreen(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )
        let right = WindowControlScreen(
            id: 2,
            frame: CGRect(x: 1000, y: 0, width: 1200, height: 900),
            visibleFrame: CGRect(x: 1000, y: 0, width: 1200, height: 900)
        )
        XCTAssertEqual(
            WindowScreenDetector.desktopBounds(for: [left, right]),
            CGRect(x: 0, y: 0, width: 2200, height: 900)
        )
    }

    func testNextAndPreviousDisplayReturnNilForSingleDisplay() {
        let screen = WindowControlScreen(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )
        let detector = WindowScreenDetector(screens: [screen])

        XCTAssertNil(detector.nextScreen(after: screen))
        XCTAssertNil(detector.previousScreen(before: screen))
    }

    func testConvertsAppKitVisibleFrameToCGDisplayCoordinates() {
        let appKitFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let appKitVisibleFrame = CGRect(x: 0, y: 50, width: 1440, height: 825)
        let cgDisplayBounds = CGRect(x: 0, y: 0, width: 1440, height: 900)

        let converted = WindowScreenDetector.convertAppKitRectToCGDisplayCoordinates(
            appKitRect: appKitVisibleFrame,
            appKitScreenFrame: appKitFrame,
            cgDisplayBounds: cgDisplayBounds
        )

        XCTAssertEqual(converted, CGRect(x: 0, y: 25, width: 1440, height: 825))
    }

    func testConvertsCGDisplayFrameBackToAppKitCoordinates() {
        let appKitFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let cgDisplayBounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let cgFrame = CGRect(x: 0, y: 25, width: 1440, height: 412.5)

        let converted = WindowScreenDetector.convertCGDisplayRectToAppKitCoordinates(
            cgRect: cgFrame,
            appKitScreenFrame: appKitFrame,
            cgDisplayBounds: cgDisplayBounds
        )

        XCTAssertEqual(converted, CGRect(x: 0, y: 462.5, width: 1440, height: 412.5))
    }

    func testPointConversionMatchesPerDisplayMathForOffsetStackedDisplays() {
        // Upper display sits above the primary in AppKit but uses negative CG Y.
        let layout = [
            WindowScreenDetector.ScreenLayoutPair(
                appKitFrame: CGRect(x: 200, y: 800, width: 1200, height: 900),
                cgBounds: CGRect(x: 200, y: -900, width: 1200, height: 900)
            ),
            WindowScreenDetector.ScreenLayoutPair(
                appKitFrame: CGRect(x: 0, y: 0, width: 1440, height: 800),
                cgBounds: CGRect(x: 0, y: 0, width: 1440, height: 800)
            )
        ]

        let appKitPoint = CGPoint(x: 800, y: 1250)
        let cgPoint = WindowScreenDetector.cgPoint(fromAppKit: appKitPoint, layout: layout)
        XCTAssertEqual(cgPoint.x, 800, accuracy: 0.5)
        XCTAssertEqual(cgPoint.y, -450, accuracy: 0.5)

        let legacyFlipY = (layout.map(\.appKitFrame.maxY).max() ?? 0) - appKitPoint.y
        XCTAssertNotEqual(cgPoint.y, legacyFlipY, accuracy: 0.5)

        let roundTrip = WindowScreenDetector.appKitPoint(fromCG: cgPoint, layout: layout)
        XCTAssertEqual(roundTrip.x, appKitPoint.x, accuracy: 0.5)
        XCTAssertEqual(roundTrip.y, appKitPoint.y, accuracy: 0.5)
    }
}
