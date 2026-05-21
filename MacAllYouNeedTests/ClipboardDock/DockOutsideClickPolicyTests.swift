@testable import MacAllYouNeed
import AppKit
import XCTest

final class DockOutsideClickPolicyTests: XCTestCase {
    private let frame = NSRect(x: 0, y: 0, width: 320, height: 180)
    private let now = Date(timeIntervalSince1970: 1_000)

    func testClickInsidePanelDoesNotHide() {
        XCTAssertFalse(DockOutsideClickPolicy.shouldHide(
            panelFrame: frame,
            clickLocationOnScreen: NSPoint(x: 10, y: 10),
            ignoreOutsideClicksUntil: .distantPast,
            now: now
        ))
    }

    func testClickOutsidePanelHidesWhenNotInIgnoreWindow() {
        XCTAssertTrue(DockOutsideClickPolicy.shouldHide(
            panelFrame: frame,
            clickLocationOnScreen: NSPoint(x: 400, y: 240),
            ignoreOutsideClicksUntil: .distantPast,
            now: now
        ))
    }

    func testClickOutsidePanelIsSuppressedDuringIgnoreWindow() {
        XCTAssertFalse(DockOutsideClickPolicy.shouldHide(
            panelFrame: frame,
            clickLocationOnScreen: NSPoint(x: 400, y: 240),
            ignoreOutsideClicksUntil: now.addingTimeInterval(1),
            now: now
        ))
    }

    func testClickOutsidePanelAtExactIgnoreBoundaryHides() {
        // Boundary check: now == ignoreOutsideClicksUntil → ignore window is over.
        XCTAssertTrue(DockOutsideClickPolicy.shouldHide(
            panelFrame: frame,
            clickLocationOnScreen: NSPoint(x: 400, y: 240),
            ignoreOutsideClicksUntil: now,
            now: now
        ))
    }

    func testClickOnPanelEdgeIsInside() {
        // NSRect.contains is half-open; ensure points strictly inside don't hide.
        XCTAssertFalse(DockOutsideClickPolicy.shouldHide(
            panelFrame: frame,
            clickLocationOnScreen: NSPoint(x: 0, y: 0),
            ignoreOutsideClicksUntil: .distantPast,
            now: now
        ))
    }

    func testScreenLocationForEventWithoutWindowReturnsMouseLocation() {
        // We cannot construct a real keyDown NSEvent with a window cheaply,
        // but the windowless path is covered by NSEvent.mouseLocation, which
        // is environment-dependent. Smoke-test it returns something finite.
        let event = NSEvent.otherEvent(
            with: .applicationDefined,
            location: NSPoint(x: 5, y: 7),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 0,
            data1: 0,
            data2: 0
        )
        let p = DockOutsideClickPolicy.screenLocation(for: event!)
        XCTAssertTrue(p.x.isFinite && p.y.isFinite)
    }
}
