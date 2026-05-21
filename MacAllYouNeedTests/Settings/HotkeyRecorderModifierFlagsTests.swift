@testable import MacAllYouNeed
import Carbon.HIToolbox
import CoreGraphics
import Platform
import XCTest

/// Pins the current behavior of `tapKeyFromCGFlags(_:)` in HotkeyRecorder.RecorderView.
///
/// For each of the 8 physical modifier positions, we synthesize a CGEventFlags that
/// includes both the generic mask (required by the guard at `held` site) AND the
/// device bit. We assert the function returns the expected `.leftX` / `.rightX` key.
///
/// The method is `internal` via `@testable import` (changed from `private` during Step C).
@MainActor
final class HotkeyRecorderModifierFlagsTests: XCTestCase {

    private var recorder: HotkeyRecorder.RecorderView!

    override func setUp() {
        super.setUp()
        var descriptor = HotkeyDescriptor(keyCode: 0, modifiers: [])
        recorder = HotkeyRecorder.RecorderView(
            descriptor: .init(get: { descriptor }, set: { descriptor = $0 })
        )
    }

    override func tearDown() {
        recorder = nil
        super.tearDown()
    }

    // MARK: - Left Command  (device bit 0x00000008)

    func testLeftCommandAloneYieldsLeftCommand() {
        // maskCommand = 0x00100000, leftCmd device bit = 0x00000008
        let flags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x00000008)
        XCTAssertEqual(recorder.tapKeyFromCGFlags(flags), .leftCommand)
    }

    // MARK: - Right Command  (device bit 0x00000010)

    func testRightCommandAloneYieldsRightCommand() {
        let flags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x00000010)
        XCTAssertEqual(recorder.tapKeyFromCGFlags(flags), .rightCommand)
    }

    // MARK: - Left Option  (device bit 0x00000020)

    func testLeftOptionAloneYieldsLeftOption() {
        // maskAlternate = 0x00080000
        let flags = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x00000020)
        XCTAssertEqual(recorder.tapKeyFromCGFlags(flags), .leftOption)
    }

    // MARK: - Right Option  (device bit 0x00000040)

    func testRightOptionAloneYieldsRightOption() {
        let flags = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x00000040)
        XCTAssertEqual(recorder.tapKeyFromCGFlags(flags), .rightOption)
    }

    // MARK: - Left Shift  (device bit 0x00000002)

    func testLeftShiftAloneYieldsLeftShift() {
        // maskShift = 0x00020000
        let flags = CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | 0x00000002)
        XCTAssertEqual(recorder.tapKeyFromCGFlags(flags), .leftShift)
    }

    // MARK: - Right Shift  (device bit 0x00000004)

    func testRightShiftAloneYieldsRightShift() {
        let flags = CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | 0x00000004)
        XCTAssertEqual(recorder.tapKeyFromCGFlags(flags), .rightShift)
    }

    // MARK: - Left Control  (device bit 0x00000001)

    func testLeftControlAloneYieldsLeftControl() {
        // maskControl = 0x00040000
        let flags = CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | 0x00000001)
        XCTAssertEqual(recorder.tapKeyFromCGFlags(flags), .leftControl)
    }

    // MARK: - Right Control  (device bit 0x00002000)

    func testRightControlAloneYieldsRightControl() {
        let flags = CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | 0x00002000)
        XCTAssertEqual(recorder.tapKeyFromCGFlags(flags), .rightControl)
    }

    // MARK: - Two families → nil (not a single tap)

    func testTwoModifierFamiliesYieldsNil() {
        let flags = CGEventFlags(
            rawValue: CGEventFlags.maskCommand.rawValue
                | CGEventFlags.maskAlternate.rawValue
                | 0x00000008  // leftCmd
                | 0x00000020  // leftOpt
        )
        XCTAssertNil(recorder.tapKeyFromCGFlags(flags))
    }

    // MARK: - No modifiers → nil

    func testNoModifiersYieldsNil() {
        XCTAssertNil(recorder.tapKeyFromCGFlags([]))
    }

    // MARK: - Fn alone → .fn

    func testFnAloneYieldsFn() {
        XCTAssertEqual(recorder.tapKeyFromCGFlags([.maskSecondaryFn]), .fn)
    }
}
