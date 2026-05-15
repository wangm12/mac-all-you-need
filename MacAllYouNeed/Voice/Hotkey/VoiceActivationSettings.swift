import Carbon.HIToolbox
import Core
import Foundation
import Platform

enum VoiceActivationMode: String, CaseIterable, Codable, Equatable, Identifiable, SegmentedTabDestination {
    case toggle
    case hold

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .toggle:
            "Press to start, press again to stop"
        case .hold:
            "Hold to talk"
        }
    }

    var title: String {
        switch self {
        case .toggle:
            "Toggle"
        case .hold:
            "Hold"
        }
    }

    var symbolName: String {
        switch self {
        case .toggle:
            "repeat"
        case .hold:
            "hand.raised"
        }
    }
}

struct VoiceActivationSettings: Codable, Equatable {
    var shortcut: HotkeyDescriptor
    var mode: VoiceActivationMode

    static let `default` = VoiceActivationSettings(
        shortcut: HotkeyDescriptor(keyCode: UInt32(kVK_Space), modifiers: [.control, .option]),
        mode: .toggle
    )
}

enum VoiceActivationSettingsStore {
    private static let key = "voice.activation.settings.v1"

    static func load(from defaults: UserDefaults = AppGroupSettings.defaults) -> VoiceActivationSettings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(VoiceActivationSettings.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    static func save(_ settings: VoiceActivationSettings, to defaults: UserDefaults = AppGroupSettings.defaults) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
