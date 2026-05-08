import Core
import Foundation
import Platform

enum HotkeyAction: String, CaseIterable, Identifiable {
    case clipboard, addDownload, browseFolder
    var id: String { rawValue }
    var label: String {
        switch self {
        case .clipboard: return "Open clipboard dock"
        case .addDownload: return "Add download"
        case .browseFolder: return "Browse folder"
        }
    }
}

enum HotkeyMapStore {
    static let key = "hotkeyMap"

    static func load() -> [HotkeyAction: HotkeyDescriptor] {
        var defaults: [HotkeyAction: HotkeyDescriptor] = [
            .clipboard: .defaultClipboard,
            .addDownload: .defaultDownload,
            .browseFolder: .defaultFolder
        ]
        if let data = AppGroupSettings.defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: HotkeyDescriptor].self, from: data)
        {
            for (rawKey, descriptor) in decoded {
                if let action = HotkeyAction(rawValue: rawKey) { defaults[action] = descriptor }
            }
        }
        return defaults
    }

    static func save(_ map: [HotkeyAction: HotkeyDescriptor]) {
        let dict = Dictionary(uniqueKeysWithValues: map.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(dict) {
            AppGroupSettings.defaults.set(data, forKey: key)
        }
    }
}
