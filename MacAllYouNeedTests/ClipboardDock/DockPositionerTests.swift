@testable import MacAllYouNeed
import AppKit
import XCTest

final class DockPositionerTests: XCTestCase {
    func testDockFrameAnchorsToBottomOfScreenWithFullWidth() throws {
        // Pick a screen we know exists when XCTest is running with an
        // AppKit context. Falling back to .main keeps headless CI safe.
        guard let screen = NSScreen.main else {
            throw XCTSkip("Headless environment: no NSScreen.main")
        }
        let frame = DockPositioner.dockFrame(forScreen: screen, height: 360)

        XCTAssertEqual(frame.minX, screen.frame.minX)
        XCTAssertEqual(frame.minY, screen.frame.minY)
        XCTAssertEqual(frame.width, screen.frame.width)
        XCTAssertEqual(frame.height, 360)
    }

    func testDockFrameRespectsArbitraryHeight() throws {
        guard let screen = NSScreen.main else {
            throw XCTSkip("Headless environment: no NSScreen.main")
        }
        let frame = DockPositioner.dockFrame(forScreen: screen, height: 720)
        XCTAssertEqual(frame.height, 720)
        // Ensure it stays bottom-flush regardless of height.
        XCTAssertEqual(frame.minY, screen.frame.minY)
    }

    func testDockFrameWithZeroHeightCollapsesToBottomLine() throws {
        guard let screen = NSScreen.main else {
            throw XCTSkip("Headless environment: no NSScreen.main")
        }
        let frame = DockPositioner.dockFrame(forScreen: screen, height: 0)
        XCTAssertEqual(frame.height, 0)
        XCTAssertEqual(frame.minY, screen.frame.minY)
        XCTAssertEqual(frame.width, screen.frame.width)
    }

    func testScreenWithCursorReturnsAScreenOrNil() {
        // Pure smoke test — the function is environment-dependent but must
        // never crash. In test environments the cursor may not be over any
        // visible screen, so nil is a valid result.
        _ = DockPositioner.screenWithCursor()
    }
}
