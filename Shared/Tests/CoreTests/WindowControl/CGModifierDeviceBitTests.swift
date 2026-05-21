import CoreGraphics
import XCTest

@testable import Core

/// Pins the CGModifierDeviceBit enum values and mask(for:) lookup.
/// These tests compile only after Step B adds CGModifierDeviceBit.
final class CGModifierDeviceBitTests: XCTestCase {

    // MARK: - Individual constant values

    func testLeftControlBit() {
        XCTAssertEqual(CGModifierDeviceBit.leftControl, 0x00000001)
    }

    func testLeftShiftBit() {
        XCTAssertEqual(CGModifierDeviceBit.leftShift, 0x00000002)
    }

    func testRightShiftBit() {
        XCTAssertEqual(CGModifierDeviceBit.rightShift, 0x00000004)
    }

    func testLeftCommandBit() {
        XCTAssertEqual(CGModifierDeviceBit.leftCommand, 0x00000008)
    }

    func testRightCommandBit() {
        XCTAssertEqual(CGModifierDeviceBit.rightCommand, 0x00000010)
    }

    func testLeftOptionBit() {
        XCTAssertEqual(CGModifierDeviceBit.leftOption, 0x00000020)
    }

    func testRightOptionBit() {
        XCTAssertEqual(CGModifierDeviceBit.rightOption, 0x00000040)
    }

    func testRightControlBit() {
        XCTAssertEqual(CGModifierDeviceBit.rightControl, 0x00002000)
    }

    // MARK: - mask(for:) keyCode lookup

    /// keyCode 54 = right Command
    func testMaskForRightCommand() {
        XCTAssertEqual(CGModifierDeviceBit.mask(for: 54), CGModifierDeviceBit.rightCommand)
    }

    /// keyCode 55 = left Command
    func testMaskForLeftCommand() {
        XCTAssertEqual(CGModifierDeviceBit.mask(for: 55), CGModifierDeviceBit.leftCommand)
    }

    /// keyCode 56 = left Shift
    func testMaskForLeftShift() {
        XCTAssertEqual(CGModifierDeviceBit.mask(for: 56), CGModifierDeviceBit.leftShift)
    }

    /// keyCode 58 = left Option
    func testMaskForLeftOption() {
        XCTAssertEqual(CGModifierDeviceBit.mask(for: 58), CGModifierDeviceBit.leftOption)
    }

    /// keyCode 59 = left Control
    func testMaskForLeftControl() {
        XCTAssertEqual(CGModifierDeviceBit.mask(for: 59), CGModifierDeviceBit.leftControl)
    }

    /// keyCode 60 = right Shift
    func testMaskForRightShift() {
        XCTAssertEqual(CGModifierDeviceBit.mask(for: 60), CGModifierDeviceBit.rightShift)
    }

    /// keyCode 61 = right Option
    func testMaskForRightOption() {
        XCTAssertEqual(CGModifierDeviceBit.mask(for: 61), CGModifierDeviceBit.rightOption)
    }

    /// keyCode 62 = right Control
    func testMaskForRightControl() {
        XCTAssertEqual(CGModifierDeviceBit.mask(for: 62), CGModifierDeviceBit.rightControl)
    }

    // MARK: - Non-modifier keys return nil

    func testMaskForNonModifierKeyReturnsNil() {
        // kVK_ANSI_A = 0
        XCTAssertNil(CGModifierDeviceBit.mask(for: 0))
    }

    func testMaskForSpaceReturnsNil() {
        // kVK_Space = 49
        XCTAssertNil(CGModifierDeviceBit.mask(for: 49))
    }

    func testMaskForReturnReturnsNil() {
        // kVK_Return = 36
        XCTAssertNil(CGModifierDeviceBit.mask(for: 36))
    }

    func testMaskForCapsLockReturnsNil() {
        // kVK_CapsLock = 57 — caps is not in our 8-bit set
        XCTAssertNil(CGModifierDeviceBit.mask(for: 57))
    }

    func testMaskForFnReturnsNil() {
        // kVK_Function = 63 — fn handled via maskSecondaryFn, not device bits
        XCTAssertNil(CGModifierDeviceBit.mask(for: 63))
    }
}
