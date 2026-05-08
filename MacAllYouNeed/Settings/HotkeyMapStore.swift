import Core
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

    static func load() -> [HotkeyAction: [HotkeyDescriptor]] {
        var defaults: [HotkeyAction: [HotkeyDescriptor]] = [
            .clipboard: [.defaultClipboard],
            .addDownload: [.defaultDownload],
            .browseFolder: [.defaultFolder]
        ]

        if let data = AppGroupSettings.defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: [HotkeyDescriptor]].self, from: data)
        {
            for (rawKey, descriptors) in decoded {
                guard let action = HotkeyAction(rawValue: rawKey) else { continue }
                defaults[action] = descriptors.isEmpty ? [action.defaultDescriptor] : descriptors
            }
        }

        return defaults
    }

    static func save(_ map: [HotkeyAction: [HotkeyDescriptor]]) {
        let dict = Dictionary(uniqueKeysWithValues: map.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(dict) {
            AppGroupSettings.defaults.set(data, forKey: key)
        }
    }
}
