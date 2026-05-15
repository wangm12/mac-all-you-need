import Core
import AppKit
import Carbon.HIToolbox
import Foundation
import Platform

enum HotkeyAction: String, CaseIterable, Identifiable {
    case clipboard
    case browseFolder

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clipboard:
            return "Open clipboard popup"
        case .browseFolder:
            return "Folder preview"
        }
    }

    var defaultDescriptor: HotkeyDescriptor {
        switch self {
        case .clipboard:
            return .defaultClipboard
        case .browseFolder:
            return .defaultFolder
        }
    }
}

enum HotkeyMapStore {
    static let key = "hotkeyMapV2"
    /// Pre-Phase-C key holding `[String: HotkeyDescriptor]`. Migrated to V2 on
    /// first read; deleted afterward so we never re-import.
    static let legacyKey = "hotkeyMap"
    static var defaultMap: [HotkeyAction: [HotkeyDescriptor]] {
        [
            .clipboard: [.defaultClipboard],
            .browseFolder: [.defaultFolder]
        ]
    }

    static func load(from defaults: UserDefaults = AppGroupSettings.defaults) -> [HotkeyAction: [HotkeyDescriptor]] {
        var result = defaultMap

        // One-shot migration: when V2 is missing but V1 exists, lift each
        // single descriptor into a one-element array, persist as V2, drop V1.
        if defaults.data(forKey: key) == nil,
           let legacyData = defaults.data(forKey: legacyKey),
           let legacy = try? JSONDecoder().decode([String: HotkeyDescriptor].self, from: legacyData)
        {
            var migrated: [HotkeyAction: [HotkeyDescriptor]] = result
            for (rawKey, descriptor) in legacy {
                guard let action = HotkeyAction(rawValue: rawKey) else { continue }
                migrated[action] = [descriptor]
            }
            save(migrated, to: defaults)
            defaults.removeObject(forKey: legacyKey)
            return migrated
        }

        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: [HotkeyDescriptor]].self, from: data)
        {
            for (rawKey, descriptors) in decoded {
                guard let action = HotkeyAction(rawValue: rawKey) else { continue }
                result[action] = descriptors.isEmpty ? [action.defaultDescriptor] : descriptors
            }
        }

        return result
    }

    static func save(_ map: [HotkeyAction: [HotkeyDescriptor]], to defaults: UserDefaults = AppGroupSettings.defaults) {
        let dict = Dictionary(uniqueKeysWithValues: map.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(dict) {
            defaults.set(data, forKey: key)
        }
    }
}

struct HotkeyValidationIssue: Equatable {
    let message: String
}

enum SystemHotkeyConflictDetector {
    static let conflictMessage = "This shortcut is already used by macOS."

    static func currentEnabledSymbolicHotkeys() -> Set<HotkeyDescriptor> {
        guard let raw = CFPreferencesCopyAppValue(
            "AppleSymbolicHotKeys" as CFString,
            "com.apple.symbolichotkeys" as CFString
        ) as? [String: Any] else {
            return []
        }
        return enabledSymbolicHotkeys(from: raw)
    }

    static func enabledSymbolicHotkeys(from raw: [String: Any]) -> Set<HotkeyDescriptor> {
        var descriptors: Set<HotkeyDescriptor> = []

        for value in raw.values {
            guard let entry = value as? [String: Any],
                  boolValue(entry["enabled"]) == true,
                  let shortcutValue = entry["value"] as? [String: Any],
                  shortcutValue["type"] as? String == "standard",
                  let parameters = shortcutValue["parameters"] as? [Any],
                  parameters.count >= 3,
                  let keyCode = intValue(parameters[1]),
                  keyCode >= 0,
                  keyCode != 65_535,
                  let rawModifiers = intValue(parameters[2])
            else { continue }

            let modifiers = modifiers(fromSymbolicHotkeyFlags: UInt(rawModifiers))
            guard !modifiers.isEmpty else { continue }
            descriptors.insert(HotkeyDescriptor(keyCode: UInt32(keyCode), modifiers: modifiers))
        }

        return descriptors
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let value as Bool:
            value
        case let value as NSNumber:
            value.boolValue
        case let value as Int:
            value != 0
        default:
            nil
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let value as Int:
            value
        case let value as NSNumber:
            value.intValue
        default:
            nil
        }
    }

    private static func modifiers(fromSymbolicHotkeyFlags rawValue: UInt) -> HotkeyDescriptor.Modifiers {
        let flags = NSEvent.ModifierFlags(rawValue: rawValue)
        var modifiers: HotkeyDescriptor.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }
}

enum HotkeyValidation {
    static func issue(
        forVoiceShortcut descriptor: HotkeyDescriptor,
        appHotkeys: [HotkeyAction: [HotkeyDescriptor]],
        systemHotkeys: Set<HotkeyDescriptor> = SystemHotkeyConflictDetector.currentEnabledSymbolicHotkeys()
    ) -> HotkeyValidationIssue? {
        if isReservedForSystemUse(descriptor) {
            return HotkeyValidationIssue(message: "This shortcut is reserved for system use.")
        }
        if systemHotkeys.contains(descriptor) {
            return HotkeyValidationIssue(message: SystemHotkeyConflictDetector.conflictMessage)
        }

        for action in HotkeyAction.allCases {
            guard appHotkeys[action]?.contains(descriptor) == true else { continue }
            return HotkeyValidationIssue(message: "This shortcut is already used by \(action.label).")
        }

        return nil
    }

    static func issue(
        forAppHotkey descriptor: HotkeyDescriptor,
        action currentAction: HotkeyAction,
        index currentIndex: Int,
        appHotkeys: [HotkeyAction: [HotkeyDescriptor]],
        voiceShortcut: HotkeyDescriptor? = nil,
        systemHotkeys: Set<HotkeyDescriptor> = SystemHotkeyConflictDetector.currentEnabledSymbolicHotkeys()
    ) -> HotkeyValidationIssue? {
        issue(
            for: descriptor,
            appHotkeys: appHotkeys,
            voiceShortcut: voiceShortcut,
            systemHotkeys: systemHotkeys,
            ignoring: HotkeyField(action: currentAction, index: currentIndex)
        )
    }

    static func firstIssue(
        in appHotkeys: [HotkeyAction: [HotkeyDescriptor]],
        voiceShortcut: HotkeyDescriptor? = nil,
        systemHotkeys: Set<HotkeyDescriptor> = SystemHotkeyConflictDetector.currentEnabledSymbolicHotkeys()
    ) -> HotkeyValidationIssue? {
        for action in HotkeyAction.allCases {
            let descriptors = appHotkeys[action] ?? []
            for (index, descriptor) in descriptors.enumerated() {
                if let issue = issue(
                    for: descriptor,
                    appHotkeys: appHotkeys,
                    voiceShortcut: voiceShortcut,
                    systemHotkeys: systemHotkeys,
                    ignoring: HotkeyField(action: action, index: index)
                ) {
                    return issue
                }
            }
        }

        return nil
    }

    private struct HotkeyField: Equatable {
        let action: HotkeyAction
        let index: Int
    }

    private static func issue(
        for descriptor: HotkeyDescriptor,
        appHotkeys: [HotkeyAction: [HotkeyDescriptor]],
        voiceShortcut: HotkeyDescriptor?,
        systemHotkeys: Set<HotkeyDescriptor>,
        ignoring ignoredField: HotkeyField?
    ) -> HotkeyValidationIssue? {
        if isReservedForSystemUse(descriptor) {
            return HotkeyValidationIssue(message: "This shortcut is reserved for system use.")
        }
        if systemHotkeys.contains(descriptor) {
            return HotkeyValidationIssue(message: SystemHotkeyConflictDetector.conflictMessage)
        }

        if voiceShortcut == descriptor {
            return HotkeyValidationIssue(message: "This shortcut is already used by Voice dictation.")
        }

        for action in HotkeyAction.allCases {
            let descriptors = appHotkeys[action] ?? []
            for (index, existing) in descriptors.enumerated() where existing == descriptor {
                if ignoredField == HotkeyField(action: action, index: index) {
                    continue
                }
                return HotkeyValidationIssue(message: "This shortcut is already used by \(action.label).")
            }
        }

        return nil
    }

    private static func isReservedForSystemUse(_ descriptor: HotkeyDescriptor) -> Bool {
        if descriptor.modifiers.isEmpty {
            return true
        }

        let commandOnly = descriptor.modifiers == [.command]
        if commandOnly, [UInt32(kVK_Space), UInt32(kVK_Tab), UInt32(kVK_Escape)].contains(descriptor.keyCode) {
            return true
        }

        let commandShift = descriptor.modifiers == [.command, .shift]
        if commandShift, [UInt32(kVK_ANSI_3), UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5)].contains(descriptor.keyCode) {
            return true
        }

        if descriptor.modifiers == [.command, .option], descriptor.keyCode == UInt32(kVK_Escape) {
            return true
        }

        if descriptor.modifiers == [.control], descriptor.keyCode == UInt32(kVK_Space) {
            return true
        }

        if descriptor.modifiers == [.control, .command], descriptor.keyCode == UInt32(kVK_Space) {
            return true
        }

        return false
    }
}
