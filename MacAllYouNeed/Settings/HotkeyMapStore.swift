import Core
import AppKit
import Carbon.HIToolbox
import Foundation
import Platform

enum HotkeyAction: String, CaseIterable, Identifiable {
    case clipboard
    case browseFolder
    case finderHistory
    case windowLeftHalf
    case windowRightHalf
    case windowTopHalf
    case windowBottomHalf
    case windowTopLeft
    case windowTopRight
    case windowBottomLeft
    case windowBottomRight
    case windowMaximize
    case windowAlmostMaximize
    case windowCenter
    case windowRestore
    case windowNextDisplay
    case windowPreviousDisplay
    case windowNextSpace
    case windowPreviousSpace
    case radialMenu
    case windowHub

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clipboard:
            return "Open clipboard popup"
        case .browseFolder:
            return "Folder preview"
        case .finderHistory:
            return "Finder History switcher"
        case .windowLeftHalf:
            return "Window Layouts: Left half"
        case .windowRightHalf:
            return "Window Layouts: Right half"
        case .windowTopHalf:
            return "Window Layouts: Top half"
        case .windowBottomHalf:
            return "Window Layouts: Bottom half"
        case .windowTopLeft:
            return "Window Layouts: Top left"
        case .windowTopRight:
            return "Window Layouts: Top right"
        case .windowBottomLeft:
            return "Window Layouts: Bottom left"
        case .windowBottomRight:
            return "Window Layouts: Bottom right"
        case .windowMaximize:
            return "Window Layouts: Maximize"
        case .windowAlmostMaximize:
            return "Window Layouts: Almost maximize"
        case .windowCenter:
            return "Window Layouts: Center"
        case .windowRestore:
            return "Window Layouts: Restore"
        case .windowNextDisplay:
            return "Window Layouts: Next display"
        case .windowPreviousDisplay:
            return "Window Layouts: Previous display"
        case .windowNextSpace:
            return "Window Layouts: Next space"
        case .windowPreviousSpace:
            return "Window Layouts: Previous space"
        case .radialMenu:
            return "Radial Menu"
        case .windowHub:
            return "Open Window Hub"
        }
    }

    var defaultDescriptors: [HotkeyDescriptor] {
        switch self {
        case .clipboard:
            return [.defaultClipboard]
        case .browseFolder:
            return [.defaultFolder]
        case .finderHistory:
            return [.defaultFolderHistory]
        case .windowLeftHalf:
            return [HotkeyDescriptor(keyCode: UInt32(kVK_LeftArrow), modifiers: [.control, .option])]
        case .windowRightHalf:
            return [HotkeyDescriptor(keyCode: UInt32(kVK_RightArrow), modifiers: [.control, .option])]
        case .windowTopHalf:
            return [HotkeyDescriptor(keyCode: UInt32(kVK_UpArrow), modifiers: [.control, .option])]
        case .windowBottomHalf:
            return [HotkeyDescriptor(keyCode: UInt32(kVK_DownArrow), modifiers: [.control, .option])]
        case .windowMaximize:
            return [HotkeyDescriptor(keyCode: UInt32(kVK_Return), modifiers: [.control, .option])]
        case .windowCenter:
            return [HotkeyDescriptor(keyCode: UInt32(kVK_ANSI_C), modifiers: [.control, .option])]
        case .windowRestore:
            return [HotkeyDescriptor(keyCode: UInt32(kVK_ANSI_R), modifiers: [.control, .option])]
        case .windowTopLeft, .windowTopRight, .windowBottomLeft, .windowBottomRight,
             .windowAlmostMaximize, .windowNextDisplay, .windowPreviousDisplay,
             .windowNextSpace, .windowPreviousSpace:
            return []
        case .radialMenu:
            return []
        case .windowHub:
            return [.defaultWindowHub]
        }
    }

    var primaryDefaultDescriptor: HotkeyDescriptor? {
        defaultDescriptors.first
    }

    var isWindowControlAction: Bool {
        switch self {
        case .clipboard, .browseFolder, .finderHistory, .windowHub:
            return false
        case .windowLeftHalf, .windowRightHalf, .windowTopHalf, .windowBottomHalf,
             .windowTopLeft, .windowTopRight, .windowBottomLeft, .windowBottomRight,
             .windowMaximize, .windowAlmostMaximize, .windowCenter, .windowRestore,
             .windowNextDisplay, .windowPreviousDisplay,
             .windowNextSpace, .windowPreviousSpace, .radialMenu:
            return true
        }
    }

    fileprivate var usesV2EmptyArrayAsDefault: Bool {
        switch self {
        case .clipboard, .browseFolder, .finderHistory, .windowHub:
            return true
        case .windowLeftHalf, .windowRightHalf, .windowTopHalf, .windowBottomHalf,
             .windowTopLeft, .windowTopRight, .windowBottomLeft, .windowBottomRight,
             .windowMaximize, .windowAlmostMaximize, .windowCenter, .windowRestore,
             .windowNextDisplay, .windowPreviousDisplay,
             .windowNextSpace, .windowPreviousSpace, .radialMenu:
            return false
        }
    }

    fileprivate func normalizedV3Descriptors(_ descriptors: [HotkeyDescriptor]) -> [HotkeyDescriptor] {
        switch self {
        case .windowLeftHalf
            where descriptors == [HotkeyDescriptor(keyCode: UInt32(kVK_LeftArrow), modifiers: [.command, .shift])]:
            return defaultDescriptors
        case .windowRightHalf
            where descriptors == [HotkeyDescriptor(keyCode: UInt32(kVK_RightArrow), modifiers: [.command, .shift])]:
            return defaultDescriptors
        default:
            return descriptors
        }
    }
}

enum HotkeyMapStore {
    static let v3Key = "hotkeyMapV3"
    static let v2Key = "hotkeyMapV2"
    static let key = v2Key
    /// Pre-Phase-C key holding `[String: HotkeyDescriptor]`. Migrated to V2 on
    /// first read; deleted afterward so we never re-import.
    static let legacyKey = "hotkeyMap"
    static var defaultMap: [HotkeyAction: [HotkeyDescriptor]] {
        Dictionary(uniqueKeysWithValues: HotkeyAction.allCases.map { ($0, $0.defaultDescriptors) })
    }

    static func load(from defaults: UserDefaults = AppGroupSettings.defaults) -> [HotkeyAction: [HotkeyDescriptor]] {
        var result = defaultMap

        if let data = defaults.data(forKey: v3Key),
           let decoded = try? JSONDecoder().decode([String: [HotkeyDescriptor]].self, from: data)
        {
            var didNormalize = false
            for (rawKey, descriptors) in decoded {
                guard let action = HotkeyAction(rawValue: rawKey) else { continue }
                let normalized = action.normalizedV3Descriptors(descriptors)
                didNormalize = didNormalize || normalized != descriptors
                result[action] = normalized
            }
            if didNormalize {
                save(result, to: defaults)
            }
            return result
        }

        if let data = defaults.data(forKey: v2Key),
           let decoded = try? JSONDecoder().decode([String: [HotkeyDescriptor]].self, from: data)
        {
            for (rawKey, descriptors) in decoded {
                guard let action = HotkeyAction(rawValue: rawKey) else { continue }
                if descriptors.isEmpty, action.usesV2EmptyArrayAsDefault {
                    result[action] = action.defaultDescriptors
                } else {
                    result[action] = descriptors
                }
            }
            save(result, to: defaults)
            defaults.removeObject(forKey: v2Key)
            return result
        }

        // One-shot migration: when V3/V2 is missing but V1 exists, lift each
        // single descriptor into a one-element array, persist as V3, drop V1.
        if defaults.data(forKey: v2Key) == nil,
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

        return result
    }

    static func save(_ map: [HotkeyAction: [HotkeyDescriptor]], to defaults: UserDefaults = AppGroupSettings.defaults) {
        let dict = Dictionary(uniqueKeysWithValues: map.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(dict) {
            defaults.set(data, forKey: v3Key)
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
        dockShortcuts: [ShortcutAction: [HotkeyDescriptor]] = [:],
        voiceReminderShortcut: HotkeyDescriptor? = nil,
        systemHotkeys: Set<HotkeyDescriptor> = SystemHotkeyConflictDetector.currentEnabledSymbolicHotkeys()
    ) -> HotkeyValidationIssue? {
        if let voiceReminderShortcut, descriptor == voiceReminderShortcut {
            return HotkeyValidationIssue(message: "This shortcut is already used by Voice Reminders.")
        }
        return issue(
            for: descriptor,
            appHotkeys: appHotkeys,
            voiceShortcut: nil,
            dockShortcuts: dockShortcuts,
            systemHotkeys: systemHotkeys
        )
    }

    static func issue(
        forVoiceReminderShortcut descriptor: HotkeyDescriptor,
        voiceDictationShortcut: HotkeyDescriptor,
        appHotkeys: [HotkeyAction: [HotkeyDescriptor]],
        dockShortcuts: [ShortcutAction: [HotkeyDescriptor]] = [:],
        systemHotkeys: Set<HotkeyDescriptor> = SystemHotkeyConflictDetector.currentEnabledSymbolicHotkeys()
    ) -> HotkeyValidationIssue? {
        if descriptor == voiceDictationShortcut {
            return HotkeyValidationIssue(message: "This shortcut is already used by Voice dictation.")
        }
        return issue(
            for: descriptor,
            appHotkeys: appHotkeys,
            voiceShortcut: voiceDictationShortcut,
            dockShortcuts: dockShortcuts,
            systemHotkeys: systemHotkeys
        )
    }

    static func issue(
        forAppHotkey descriptor: HotkeyDescriptor,
        action currentAction: HotkeyAction,
        index currentIndex: Int,
        appHotkeys: [HotkeyAction: [HotkeyDescriptor]],
        voiceShortcut: HotkeyDescriptor? = nil,
        dockShortcuts: [ShortcutAction: [HotkeyDescriptor]] = [:],
        systemHotkeys: Set<HotkeyDescriptor> = SystemHotkeyConflictDetector.currentEnabledSymbolicHotkeys()
    ) -> HotkeyValidationIssue? {
        issue(
            for: descriptor,
            appHotkeys: appHotkeys,
            voiceShortcut: voiceShortcut,
            dockShortcuts: dockShortcuts,
            systemHotkeys: systemHotkeys,
            ignoringApp: HotkeyField(action: currentAction, index: currentIndex)
        )
    }

    static func issue(
        forDockShortcut descriptor: HotkeyDescriptor,
        action currentAction: ShortcutAction,
        index currentIndex: Int,
        appHotkeys: [HotkeyAction: [HotkeyDescriptor]] = HotkeyMapStore.load(),
        voiceShortcut: HotkeyDescriptor? = nil,
        dockShortcuts: [ShortcutAction: [HotkeyDescriptor]],
        systemHotkeys: Set<HotkeyDescriptor> = SystemHotkeyConflictDetector.currentEnabledSymbolicHotkeys()
    ) -> HotkeyValidationIssue? {
        if let conventional = conventionalDockIssue(descriptor, action: currentAction) {
            return conventional
        }
        return issue(
            for: descriptor,
            appHotkeys: appHotkeys,
            voiceShortcut: voiceShortcut,
            dockShortcuts: dockShortcuts,
            systemHotkeys: systemHotkeys,
            ignoringDock: DockBindingField(action: currentAction, index: currentIndex)
        )
    }

    static func firstIssue(
        in appHotkeys: [HotkeyAction: [HotkeyDescriptor]],
        voiceShortcut: HotkeyDescriptor? = nil,
        dockShortcuts: [ShortcutAction: [HotkeyDescriptor]] = [:],
        systemHotkeys: Set<HotkeyDescriptor> = SystemHotkeyConflictDetector.currentEnabledSymbolicHotkeys()
    ) -> HotkeyValidationIssue? {
        for action in HotkeyAction.allCases {
            let descriptors = appHotkeys[action] ?? []
            for (index, descriptor) in descriptors.enumerated() {
                if let issue = issue(
                    for: descriptor,
                    appHotkeys: appHotkeys,
                    voiceShortcut: voiceShortcut,
                    dockShortcuts: dockShortcuts,
                    systemHotkeys: systemHotkeys,
                    ignoringApp: HotkeyField(action: action, index: index)
                ) {
                    return issue
                }
            }
        }

        for action in ShortcutAction.allCases {
            let descriptors = dockShortcuts[action] ?? []
            for (index, descriptor) in descriptors.enumerated() {
                if let conventional = conventionalDockIssue(descriptor, action: action) {
                    return conventional
                }
                if let issue = issue(
                    for: descriptor,
                    appHotkeys: appHotkeys,
                    voiceShortcut: voiceShortcut,
                    dockShortcuts: dockShortcuts,
                    systemHotkeys: systemHotkeys,
                    ignoringDock: DockBindingField(action: action, index: index)
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

    private struct DockBindingField: Equatable {
        let action: ShortcutAction
        let index: Int
    }

    private static func issue(
        for descriptor: HotkeyDescriptor,
        appHotkeys: [HotkeyAction: [HotkeyDescriptor]],
        voiceShortcut: HotkeyDescriptor?,
        dockShortcuts: [ShortcutAction: [HotkeyDescriptor]],
        systemHotkeys: Set<HotkeyDescriptor>,
        ignoringApp ignoredAppField: HotkeyField? = nil,
        ignoringDock ignoredDockField: DockBindingField? = nil
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
                if ignoredAppField == HotkeyField(action: action, index: index) {
                    continue
                }
                return HotkeyValidationIssue(message: "This shortcut is already used by \(action.label).")
            }
        }

        for action in ShortcutAction.allCases {
            let descriptors = dockShortcuts[action] ?? []
            for (index, existing) in descriptors.enumerated() where existing == descriptor {
                if ignoredDockField == DockBindingField(action: action, index: index) {
                    continue
                }
                return HotkeyValidationIssue(message: "This shortcut is already used by \(action.label).")
            }
        }

        return nil
    }

    private static func conventionalDockIssue(
        _ descriptor: HotkeyDescriptor,
        action: ShortcutAction
    ) -> HotkeyValidationIssue? {
        guard !descriptor.isModifierTap else { return nil }
        let conventional: [UInt32: ShortcutAction] = [
            UInt32(kVK_Escape): .dismiss,
            UInt32(kVK_Return): .paste,
            UInt32(kVK_Space): .cycleFocus,
            UInt32(kVK_ANSI_V): .quickLook,
            UInt32(kVK_LeftArrow): .extendSelectionLeft,
            UInt32(kVK_RightArrow): .extendSelectionRight
        ]
        guard descriptor.modifiers.isEmpty,
              let owner = conventional[descriptor.keyCode],
              owner != action
        else { return nil }
        return HotkeyValidationIssue(message: "This shortcut is reserved for \(owner.label).")
    }

    private static func isReservedForSystemUse(_ descriptor: HotkeyDescriptor) -> Bool {
        if descriptor.isModifierTap {
            return false
        }
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

    /// Live in-dock bindings for cross-surface conflict checks from settings UI.
    @MainActor
    static func liveDockShortcuts() -> [ShortcutAction: [HotkeyDescriptor]] {
        ShortcutRegistry.shared.allBindings()
    }
}
