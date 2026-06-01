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

    /// Action applied when the cursor stays in the center band.
    public static let centerAction: WindowAction = .maximize

    /// Optional keyboard shortcuts for ring + center positions.
    /// Keys that dismiss the radial menu while it is open (in addition to Esc).
    public static let dismissKeys: Set<Character> = ["x"]

    public static let keyboardMapping: [Character: WindowAction] = [
        "w": .topHalf,
        "e": .topRight,
        "d": .rightHalf,
        "c": .bottomRight,
        "s": .bottomHalf,
        "z": .bottomLeft,
        "a": .leftHalf,
        "q": .topLeft,
        "m": .maximize,
        "f": .maximize
    ]

    public static func action(forRingIndex index: Int) -> WindowAction? {
        guard index >= 0, index < ringActions.count else { return nil }
        return ringActions[index]
    }

    public static func action(forKey character: Character) -> WindowAction? {
        keyboardMapping[character]
    }

    /// Keys that select `action` while the radial menu is open (for settings reference).
    public static func inMenuShortcutDisplay(for action: WindowAction) -> String? {
        let keys = keyboardMapping.filter { $0.value == action }.map(\.key)
        guard !keys.isEmpty else { return nil }
        return keys.map { String($0).uppercased() }.sorted().joined(separator: ", ")
    }
}
