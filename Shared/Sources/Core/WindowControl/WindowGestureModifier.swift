import CoreGraphics
import Foundation

/// Physical modifier device bits encoded in CGEventFlags. macOS sets these
/// alongside the generic modifier mask so callers can disambiguate left vs
/// right modifier keys at the HID layer.
///
/// Source of truth. All call sites that need to decode physical modifier
/// presence must use this enum instead of hardcoding the hex values.
public enum CGModifierDeviceBit {
    public static let leftControl:  CGEventFlags.RawValue = 0x00000001
    public static let leftShift:    CGEventFlags.RawValue = 0x00000002
    public static let rightShift:   CGEventFlags.RawValue = 0x00000004
    public static let leftCommand:  CGEventFlags.RawValue = 0x00000008
    public static let rightCommand: CGEventFlags.RawValue = 0x00000010
    public static let leftOption:   CGEventFlags.RawValue = 0x00000020
    public static let rightOption:  CGEventFlags.RawValue = 0x00000040
    public static let rightControl: CGEventFlags.RawValue = 0x00002000

    /// Returns the device bit for the given keyCode, or nil for non-modifier keys.
    /// Maps the standard Carbon HIToolbox modifier keyCodes (54-62).
    public static func mask(for keyCode: Int64) -> CGEventFlags.RawValue? {
        switch keyCode {
        case 54: return rightCommand
        case 55: return leftCommand
        case 56: return leftShift
        case 58: return leftOption
        case 59: return leftControl
        case 60: return rightShift
        case 61: return rightOption
        case 62: return rightControl
        default: return nil
        }
    }
}

public struct WindowGestureModifier: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue & Self.knownRawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(Int.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let none: WindowGestureModifier = []
    public static let option = WindowGestureModifier(rawValue: 1 << 0)
    public static let control = WindowGestureModifier(rawValue: 1 << 1)
    public static let command = WindowGestureModifier(rawValue: 1 << 2)
    public static let shift = WindowGestureModifier(rawValue: 1 << 3)
    public static let fn = WindowGestureModifier(rawValue: 1 << 4)
    public static let leftControl = WindowGestureModifier(rawValue: 1 << 5)
    public static let rightControl = WindowGestureModifier(rawValue: 1 << 6)
    public static let leftOption = WindowGestureModifier(rawValue: 1 << 7)
    public static let rightOption = WindowGestureModifier(rawValue: 1 << 8)
    public static let leftCommand = WindowGestureModifier(rawValue: 1 << 9)
    public static let rightCommand = WindowGestureModifier(rawValue: 1 << 10)
    public static let leftShift = WindowGestureModifier(rawValue: 1 << 11)
    public static let rightShift = WindowGestureModifier(rawValue: 1 << 12)

    public init(cgEventFlags flags: CGEventFlags) {
        var modifier: WindowGestureModifier = []
        let rawFlags = flags.rawValue

        let leftControlHeld = rawFlags & CGModifierDeviceBit.leftControl != 0
        let rightControlHeld = rawFlags & CGModifierDeviceBit.rightControl != 0
        let leftOptionHeld = rawFlags & CGModifierDeviceBit.leftOption != 0
        let rightOptionHeld = rawFlags & CGModifierDeviceBit.rightOption != 0
        let leftCommandHeld = rawFlags & CGModifierDeviceBit.leftCommand != 0
        let rightCommandHeld = rawFlags & CGModifierDeviceBit.rightCommand != 0
        let leftShiftHeld = rawFlags & CGModifierDeviceBit.leftShift != 0
        let rightShiftHeld = rawFlags & CGModifierDeviceBit.rightShift != 0

        if flags.contains(.maskControl) || leftControlHeld || rightControlHeld { modifier.insert(.control) }
        if flags.contains(.maskAlternate) || leftOptionHeld || rightOptionHeld { modifier.insert(.option) }
        if flags.contains(.maskCommand) || leftCommandHeld || rightCommandHeld { modifier.insert(.command) }
        if flags.contains(.maskShift) || leftShiftHeld || rightShiftHeld { modifier.insert(.shift) }
        if flags.contains(.maskSecondaryFn) { modifier.insert(.fn) }

        if leftControlHeld { modifier.insert(.leftControl) }
        if rightControlHeld { modifier.insert(.rightControl) }
        if leftOptionHeld { modifier.insert(.leftOption) }
        if rightOptionHeld { modifier.insert(.rightOption) }
        if leftCommandHeld { modifier.insert(.leftCommand) }
        if rightCommandHeld { modifier.insert(.rightCommand) }
        if leftShiftHeld { modifier.insert(.leftShift) }
        if rightShiftHeld { modifier.insert(.rightShift) }

        self.init(rawValue: modifier.rawValue)
    }

    public var display: String {
        var names: [String] = []
        names += familyDisplay(generic: .control, left: .leftControl, right: .rightControl, name: "Control")
        names += familyDisplay(generic: .option, left: .leftOption, right: .rightOption, name: "Option")
        names += familyDisplay(generic: .command, left: .leftCommand, right: .rightCommand, name: "Command")
        names += familyDisplay(generic: .shift, left: .leftShift, right: .rightShift, name: "Shift")
        if contains(.fn) { names.append("Fn") }
        return names.isEmpty ? "None" : names.joined(separator: " + ")
    }

    public var eventFlagsDisplay: String {
        display
    }

    public func isSatisfied(by activeModifiers: WindowGestureModifier) -> Bool {
        guard !isEmpty else { return false }
        return activeModifiers.normalizedForMatching.isSuperset(of: self)
    }

    /// Option/control/command/shift family bits, folding left/right hardware variants.
    public var primaryModifierFamily: WindowGestureModifier {
        var result: WindowGestureModifier = []
        if contains(.option) || contains(.leftOption) || contains(.rightOption) { result.insert(.option) }
        if contains(.control) || contains(.leftControl) || contains(.rightControl) { result.insert(.control) }
        if contains(.command) || contains(.leftCommand) || contains(.rightCommand) { result.insert(.command) }
        if contains(.shift) || contains(.leftShift) || contains(.rightShift) { result.insert(.shift) }
        return result
    }

    /// Matches a configured grab/snap modifier against flags from a mouse event.
    ///
    /// Generic requirements (e.g. `.control`) accept either side. Side-specific
    /// requirements (e.g. `.leftControl`) still reject the opposite side, but also
    /// accept the generic family bit when macOS omits device bits on mouse events.
    public func matchesGestureHold(_ held: WindowGestureModifier) -> Bool {
        guard !isEmpty else { return false }
        if isSatisfied(by: held) { return true }

        let requiredFamily = primaryModifierFamily
        guard !requiredFamily.isEmpty, held.primaryModifierFamily == requiredFamily else { return false }

        let requiredSides = subtracting(requiredFamily)
        guard !requiredSides.isEmpty else { return false }

        let heldSides = held.subtracting(held.primaryModifierFamily)
        return heldSides.isEmpty
    }

    private static let knownRawValue =
        (1 << 0)
        | (1 << 1)
        | (1 << 2)
        | (1 << 3)
        | (1 << 4)
        | (1 << 5)
        | (1 << 6)
        | (1 << 7)
        | (1 << 8)
        | (1 << 9)
        | (1 << 10)
        | (1 << 11)
        | (1 << 12)

    private var normalizedForMatching: WindowGestureModifier {
        var modifier = self
        if !intersection([.leftControl, .rightControl]).isEmpty { modifier.insert(.control) }
        if !intersection([.leftOption, .rightOption]).isEmpty { modifier.insert(.option) }
        if !intersection([.leftCommand, .rightCommand]).isEmpty { modifier.insert(.command) }
        if !intersection([.leftShift, .rightShift]).isEmpty { modifier.insert(.shift) }
        return modifier
    }

    private func familyDisplay(
        generic: WindowGestureModifier,
        left: WindowGestureModifier,
        right: WindowGestureModifier,
        name: String
    ) -> [String] {
        let hasLeft = contains(left)
        let hasRight = contains(right)
        guard hasLeft || hasRight else {
            return contains(generic) ? [name] : []
        }

        var names: [String] = []
        if hasLeft { names.append("Left \(name)") }
        if hasRight { names.append("Right \(name)") }
        return names
    }
}
