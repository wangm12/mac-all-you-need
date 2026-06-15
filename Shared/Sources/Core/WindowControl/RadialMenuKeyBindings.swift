import Foundation

/// Per-action single-key shortcuts shown in the radial menu cheat sheet.
public struct RadialMenuKeyBindings: Codable, Equatable, Sendable {
    public var bindings: [String: String]

    public init(bindings: [String: String] = RadialMenuKeyBindings.defaultBindings) {
        self.bindings = bindings
    }

    public static let `default` = RadialMenuKeyBindings()

    public static let defaultBindings: [String: String] = [
        WindowAction.topHalf.rawValue: "w",
        WindowAction.topRight.rawValue: "e",
        WindowAction.rightHalf.rawValue: "d",
        WindowAction.bottomRight.rawValue: "c",
        WindowAction.bottomHalf.rawValue: "s",
        WindowAction.bottomLeft.rawValue: "z",
        WindowAction.leftHalf.rawValue: "a",
        WindowAction.topLeft.rawValue: "q",
        WindowAction.maximize.rawValue: "f"
    ]

    public static let reservedKeys: Set<Character> = ["x"]

    public func keyboardMapping() -> [Character: WindowAction] {
        var mapping: [Character: WindowAction] = [:]
        for (raw, key) in bindings {
            guard let action = WindowAction(rawValue: raw),
                  let character = key.lowercased().first
            else {
                continue
            }
            mapping[character] = action
        }
        if mapping["m"] == nil {
            mapping["m"] = .maximize
        }
        return mapping
    }

    public func display(for action: WindowAction) -> String? {
        let keys = bindings
            .filter { WindowAction(rawValue: $0.key) == action }
            .compactMap(\.value.first)
            .map { String($0).uppercased() }
        var sorted = keys.sorted()
        if action == .maximize, !sorted.contains("M") {
            sorted.append("M")
        }
        guard !sorted.isEmpty else { return nil }
        return sorted.joined(separator: ", ")
    }

    public func normalized() -> RadialMenuKeyBindings {
        var next = bindings
        for (action, defaultKey) in Self.defaultBindings {
            let raw = action
            guard let value = next[raw]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  let first = value.first,
                  first.isLetter,
                  !Self.reservedKeys.contains(first)
            else {
                next[raw] = defaultKey
                continue
            }
            next[raw] = String(first)
        }
        return RadialMenuKeyBindings(bindings: next)
    }

    public func replacingDuplicateKeys() -> RadialMenuKeyBindings {
        var used: Set<Character> = []
        var next: [String: String] = [:]
        for raw in Self.defaultBindings.keys.sorted() {
            let stored = bindings[raw] ?? Self.defaultBindings[raw] ?? ""
            let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let defaultKey = Self.defaultBindings[raw] ?? ""
            let resolved: String
            if let first = trimmed.first,
               first.isLetter,
               !Self.reservedKeys.contains(first),
               !used.contains(first)
            {
                resolved = String(first)
                used.insert(first)
            } else if let first = defaultKey.first, !used.contains(first) {
                resolved = defaultKey
                used.insert(first)
            } else {
                resolved = defaultKey
            }
            next[raw] = resolved
        }
        return RadialMenuKeyBindings(bindings: next).normalized()
    }
}
