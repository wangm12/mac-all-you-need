import CoreGraphics
import Foundation

/// Pure, no-AppKit layout for the radial window management menu.
/// Maps 8 outer ring positions + a center band to `WindowAction`.
public enum RadialMenuLayout {
    /// 8 outer ring segments, clockwise from top.
    public static let ringActions: [WindowAction] = [
        .topHalf, // 0: top
        .topRight, // 1: top-right
        .rightHalf, // 2: right
        .bottomRight, // 3: bottom-right
        .bottomHalf, // 4: bottom
        .bottomLeft, // 5: bottom-left
        .leftHalf, // 6: left
        .topLeft // 7: top-left
    ]

    /// Fill Screen via long-pull past the ring in any direction, or keyboard binding.
    public static let fillScreenAction: WindowAction = .maximize

    /// Deprecated center-band target; preserved for migration and keyboard mapping only.
    public static let centerAction: WindowAction = .maximize

    /// Canonical aim angle (radians, 0 = up, clockwise) for ring index.
    public static func canonicalAngleRadians(forRingIndex index: Int) -> CGFloat {
        guard index >= 0, index < ringActions.count else { return 0 }
        return CGFloat(index) * (2 * .pi / CGFloat(ringActions.count))
    }

    public static func ringIndex(for action: WindowAction) -> Int? {
        ringActions.firstIndex(of: action)
    }

    /// Optional keyboard shortcuts for ring + center positions.
    /// Keys that dismiss the radial menu while it is open (in addition to Esc).
    public static let dismissKeys: Set<Character> = ["x"]

    public static let keyboardMapping: [Character: WindowAction] = RadialMenuKeyBindings.default.keyboardMapping()

    public static func keyboardMapping(bindings: RadialMenuKeyBindings) -> [Character: WindowAction] {
        bindings.keyboardMapping()
    }

    public static func action(forRingIndex index: Int) -> WindowAction? {
        guard index >= 0, index < ringActions.count else { return nil }
        return ringActions[index]
    }

    public static func action(forKey character: Character) -> WindowAction? {
        action(forKey: character, bindings: .default)
    }

    public static func action(forKey character: Character, bindings: RadialMenuKeyBindings) -> WindowAction? {
        keyboardMapping(bindings: bindings)[character]
    }

    /// Keys that select `action` while the radial menu is open (for settings reference).
    public static func inMenuShortcutDisplay(for action: WindowAction) -> String? {
        inMenuShortcutDisplay(for: action, bindings: .default)
    }

    public static func inMenuShortcutDisplay(for action: WindowAction, bindings: RadialMenuKeyBindings) -> String? {
        bindings.display(for: action)
    }
}
