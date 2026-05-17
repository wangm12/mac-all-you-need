import CoreGraphics
import Foundation

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

        let leftControlHeld = rawFlags & Self.deviceLeftControlMask != 0
        let rightControlHeld = rawFlags & Self.deviceRightControlMask != 0
        let leftOptionHeld = rawFlags & Self.deviceLeftOptionMask != 0
        let rightOptionHeld = rawFlags & Self.deviceRightOptionMask != 0
        let leftCommandHeld = rawFlags & Self.deviceLeftCommandMask != 0
        let rightCommandHeld = rawFlags & Self.deviceRightCommandMask != 0
        let leftShiftHeld = rawFlags & Self.deviceLeftShiftMask != 0
        let rightShiftHeld = rawFlags & Self.deviceRightShiftMask != 0

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

    private static let deviceLeftControlMask: CGEventFlags.RawValue = 0x00000001
    private static let deviceLeftShiftMask: CGEventFlags.RawValue = 0x00000002
    private static let deviceRightShiftMask: CGEventFlags.RawValue = 0x00000004
    private static let deviceLeftCommandMask: CGEventFlags.RawValue = 0x00000008
    private static let deviceRightCommandMask: CGEventFlags.RawValue = 0x00000010
    private static let deviceLeftOptionMask: CGEventFlags.RawValue = 0x00000020
    private static let deviceRightOptionMask: CGEventFlags.RawValue = 0x00000040
    private static let deviceRightControlMask: CGEventFlags.RawValue = 0x00002000

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
