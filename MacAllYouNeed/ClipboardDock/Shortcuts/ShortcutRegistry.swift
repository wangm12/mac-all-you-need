import AppKit
import Core
import Foundation
import Observation

enum ShortcutValidationError: Error {
    case reservedKey(UInt16)
    case unsupportedModifier
}

@MainActor
@Observable
final class ShortcutRegistry {
    static let shared = ShortcutRegistry()
    static var testSuite: String?

    private let defaults: UserDefaults
    private var cache: [ShortcutAction: [ShortcutBinding]] = [:]

    init() {
        if let suite = Self.testSuite {
            defaults = UserDefaults(suiteName: suite) ?? .standard
        } else {
            defaults = AppGroupSettings.defaults
        }
    }

    func bindings(for action: ShortcutAction) -> [ShortcutBinding] {
        if let cached = cache[action] {
            return cached
        }

        let key = storageKey(for: action)
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ShortcutBinding].self, from: data)
        {
            cache[action] = decoded
            return decoded
        }

        let fallback = ShortcutDefaults.defaultBindings(for: action)
        cache[action] = fallback
        return fallback
    }

    func setBindings(_ bindings: [ShortcutBinding], for action: ShortcutAction) {
        cache[action] = bindings
        let key = storageKey(for: action)
        if let data = try? JSONEncoder().encode(bindings) {
            defaults.set(data, forKey: key)
        }
    }

    func addBinding(_ binding: ShortcutBinding, for action: ShortcutAction) {
        var current = bindings(for: action)
        if !current.contains(binding) {
            current.append(binding)
            setBindings(current, for: action)
        }
    }

    func removeBinding(_ binding: ShortcutBinding, for action: ShortcutAction) {
        var current = bindings(for: action)
        current.removeAll { $0 == binding }
        setBindings(current, for: action)
    }

    func reset(action: ShortcutAction) {
        defaults.removeObject(forKey: storageKey(for: action))
        cache.removeValue(forKey: action)
    }

    func validate(_ binding: ShortcutBinding, for action: ShortcutAction) throws {
        let conventional: [UInt16: ShortcutAction] = [
            53: .dismiss,
            36: .paste,
            48: .cycleFocus,
            49: .quickLook,
            123: .extendSelectionLeft,
            124: .extendSelectionRight
        ]

        if binding.modifierMask == 0,
           let owner = conventional[binding.keyCode],
           owner != action
        {
            throw ShortcutValidationError.reservedKey(binding.keyCode)
        }
    }

    func matches(event: NSEvent, _ action: ShortcutAction) -> Bool {
        let mask = NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue
        let eventMods = event.modifierFlags.rawValue & mask
        return bindings(for: action).contains { binding in
            binding.keyCode == event.keyCode && binding.modifierMask == eventMods
        }
    }

    func clearCache() {
        cache.removeAll()
    }

    private func storageKey(for action: ShortcutAction) -> String {
        "shortcut.\(action.rawValue)"
    }
}
