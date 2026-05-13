import Core
import Carbon.HIToolbox
import Foundation
import Platform

enum HotkeyAction: String, CaseIterable, Identifiable {
    case clipboard
    case addDownload
    case browseFolder

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clipboard:
            return "Open clipboard popup"
        case .addDownload:
            return "Add download"
        case .browseFolder:
            return "Browse folder"
        }
    }

    var defaultDescriptor: HotkeyDescriptor {
        switch self {
        case .clipboard:
            return .defaultClipboard
        case .addDownload:
            return .defaultDownload
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

    static func load(from defaults: UserDefaults = AppGroupSettings.defaults) -> [HotkeyAction: [HotkeyDescriptor]] {
        var result: [HotkeyAction: [HotkeyDescriptor]] = [
            .clipboard: [.defaultClipboard],
            .addDownload: [.defaultDownload],
            .browseFolder: [.defaultFolder]
        ]

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

enum HotkeyValidation {
    static func issue(
        forVoiceShortcut descriptor: HotkeyDescriptor,
        appHotkeys: [HotkeyAction: [HotkeyDescriptor]]
    ) -> HotkeyValidationIssue? {
        if isReservedForSystemUse(descriptor) {
            return HotkeyValidationIssue(message: "This shortcut is reserved for system use.")
        }

        for action in HotkeyAction.allCases {
            guard appHotkeys[action]?.contains(descriptor) == true else { continue }
            return HotkeyValidationIssue(message: "This shortcut is already used by \(action.label).")
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

        return false
    }
}
