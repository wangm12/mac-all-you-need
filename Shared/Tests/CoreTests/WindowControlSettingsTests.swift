@testable import Core
import CoreGraphics
import XCTest

final class WindowControlSettingsTests: XCTestCase {
    func testDefaultSettingsAreConservative() {
        XCTAssertFalse(WindowControlSettings.default.enabled)
        XCTAssertEqual(WindowControlSettings.default.dragModifier.display, "Option")
    }

    func testGestureModifierDisplayNames() {
        XCTAssertEqual(WindowGestureModifier.option.eventFlagsDisplay, "Option")
        XCTAssertEqual(WindowGestureModifier.fn.display, "Fn")
        XCTAssertEqual(WindowGestureModifier.leftOption.display, "Left Option")
        XCTAssertEqual(WindowGestureModifier.rightControl.display, "Right Control")

        let modifier = WindowGestureModifier([.control, .option])

        XCTAssertTrue(modifier.display.contains("Control"))
        XCTAssertTrue(modifier.display.contains("Option"))
    }

    func testGestureModifierEventFlagsPreserveGenericAndSpecificSides() {
        let modifier = WindowGestureModifier(cgEventFlags: CGEventFlags(
            rawValue: CGEventFlags.maskAlternate.rawValue | 0x00000020
        ))

        XCTAssertTrue(modifier.contains(.option))
        XCTAssertTrue(modifier.contains(.leftOption))
        XCTAssertFalse(modifier.contains(.rightOption))
    }

    func testGenericGestureModifierMatchesSpecificHeldSide() {
        XCTAssertTrue(WindowGestureModifier.option.isSatisfied(by: [.option, .leftOption]))
        XCTAssertTrue(WindowGestureModifier.option.isSatisfied(by: .leftOption))
        XCTAssertTrue(WindowGestureModifier.leftOption.isSatisfied(by: [.option, .leftOption]))
        XCTAssertFalse(WindowGestureModifier.leftOption.isSatisfied(by: .option))
    }

    func testGestureModifierDropsUnsupportedRawBits() {
        let modifier = WindowGestureModifier(rawValue: 1 << 20)

        XCTAssertEqual(modifier.display, "None")
        XCTAssertEqual(modifier.rawValue, 0)
    }

    func testGestureModifierCodableDropsUnsupportedRawBits() throws {
        let rawValue = WindowGestureModifier.option.rawValue | (1 << 20)
        let data = Data("\(rawValue)".utf8)

        let decoded = try JSONDecoder().decode(WindowGestureModifier.self, from: data)

        XCTAssertEqual(decoded, .option)
        XCTAssertEqual(decoded.rawValue, WindowGestureModifier.option.rawValue)
    }

    func testSettingsCodableRoundTrip() throws {
        var settings = WindowControlSettings.default
        settings.enabled = true
        settings.ignoredBundleIDs = ["com.example.Ignored"]
        settings.edgeSnapModifier = [.control, .option]

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(WindowControlSettings.self, from: data)

        XCTAssertEqual(decoded, settings)
    }

    func testDragEdgeSnapCanRequireConfiguredModifier() {
        var settings = WindowControlSettings.default
        settings.edgeSnapEnabled = true
        settings.edgeSnapRequiresModifier = true
        settings.edgeSnapModifier = [.control, .option]

        XCTAssertFalse(settings.allowsDragEdgeSnap(activeModifiers: .option))
        XCTAssertTrue(settings.allowsDragEdgeSnap(activeModifiers: [.control, .option]))
    }

    func testRequiredDragEdgeSnapDoesNotTreatNoneAsMatchedModifier() {
        var settings = WindowControlSettings.default
        settings.edgeSnapEnabled = true
        settings.edgeSnapRequiresModifier = true
        settings.edgeSnapModifier = .none

        XCTAssertFalse(settings.allowsDragEdgeSnap(activeModifiers: .none))
        XCTAssertFalse(settings.allowsDragEdgeSnap(activeModifiers: .option))
    }
}
