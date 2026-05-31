import AppKit
import Core
import Foundation
import Observation
import Platform

enum ShortcutValidationError: Error {
    case reservedKey(UInt16)
    case validation(String)
}

@MainActor
@Observable
final class ShortcutRegistry {
    static let shared = ShortcutRegistry()
    static var testSuite: String?

    private let defaults: UserDefaults
    private var cache: [ShortcutAction: [HotkeyDescriptor]] = [:]

    init() {
        if let suite = Self.testSuite {
            defaults = UserDefaults(suiteName: suite) ?? .standard
        } else {
            defaults = AppGroupSettings.defaults
        }
    }

    func bindings(for action: ShortcutAction) -> [HotkeyDescriptor] {
        if let cached = cache[action] {
            return cached
        }

        let key = storageKey(for: action)
        if let data = defaults.data(forKey: key) {
            if let decoded = try? JSONDecoder().decode([HotkeyDescriptor].self, from: data) {
                cache[action] = decoded
                return decoded
            }
            if let legacy = try? JSONDecoder().decode([LegacyShortcutBinding].self, from: data) {
                let migrated = legacy.map { $0.asHotkeyDescriptor() }
                cache[action] = migrated
                setBindings(migrated, for: action)
                return migrated
            }
        }

        let fallback = ShortcutDefaults.defaultBindings(for: action)
        cache[action] = fallback
        return fallback
    }

    func allBindings() -> [ShortcutAction: [HotkeyDescriptor]] {
        Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, bindings(for: $0)) })
    }

    func setBindings(_ bindings: [HotkeyDescriptor], for action: ShortcutAction) {
        cache[action] = bindings
        let key = storageKey(for: action)
        if let data = try? JSONEncoder().encode(bindings) {
            defaults.set(data, forKey: key)
        }
    }

    func addBinding(_ binding: HotkeyDescriptor, for action: ShortcutAction) {
        var current = bindings(for: action)
        if !current.contains(binding) {
            current.append(binding)
            setBindings(current, for: action)
        }
    }

    func removeBinding(_ binding: HotkeyDescriptor, for action: ShortcutAction) {
        var current = bindings(for: action)
        current.removeAll { $0 == binding }
        setBindings(current, for: action)
    }

    func reset(action: ShortcutAction) {
        defaults.removeObject(forKey: storageKey(for: action))
        cache.removeValue(forKey: action)
    }

    func validate(
        _ descriptor: HotkeyDescriptor,
        for action: ShortcutAction,
        bindingIndex: Int? = nil,
        appHotkeys: [HotkeyAction: [HotkeyDescriptor]] = HotkeyMapStore.load(),
        voiceShortcut: HotkeyDescriptor? = nil
    ) throws {
        let dockShortcuts = allBindings()
        let index = bindingIndex ?? bindings(for: action).count
        if let issue = HotkeyValidation.issue(
            forDockShortcut: descriptor,
            action: action,
            index: index,
            appHotkeys: appHotkeys,
            voiceShortcut: voiceShortcut,
            dockShortcuts: dockShortcuts
        ) {
            throw ShortcutValidationError.validation(issue.message)
        }
    }

    func matches(event: NSEvent, _ action: ShortcutAction) -> Bool {
        bindings(for: action).contains { $0.matches(event: event) }
    }

    func modifierTapBindings(for action: ShortcutAction) -> [HotkeyDescriptor] {
        bindings(for: action).filter(\.isModifierTap)
    }

    func clearCache() {
        cache.removeAll()
    }

    private func storageKey(for action: ShortcutAction) -> String {
        "shortcut.\(action.rawValue)"
    }
}
