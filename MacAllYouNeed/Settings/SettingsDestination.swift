import Foundation

enum SettingsDestination: String, CaseIterable, Identifiable {
    case clipboard
    case voice
    case downloads
    case folderPreview
    case snippets
    case hotkeys
    case search
    case permissions
    case privacy
    case storage
    case general
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clipboard: "Clipboard"
        case .voice: "Voice"
        case .downloads: "Downloads"
        case .folderPreview: "Folder Preview"
        case .snippets: "Snippets"
        case .hotkeys: "Hotkeys"
        case .search: "Search"
        case .permissions: "Permissions"
        case .privacy: "Privacy"
        case .storage: "Storage"
        case .general: "General"
        case .advanced: "Advanced"
        }
    }

    var subtitle: String {
        switch self {
        case .clipboard: "History, capture, and paste behavior"
        case .voice: "Dictation, cleanup, and app profiles"
        case .downloads: "Queue, cookies, and save location"
        case .folderPreview: "Folder and archive preview defaults"
        case .snippets: "Reusable text and expansion triggers"
        case .hotkeys: "Global and in-dock keyboard control"
        case .search: "History ranking and matching"
        case .permissions: "macOS access required by features"
        case .privacy: "Capture exclusions and filtering"
        case .storage: "Retention and maintenance"
        case .general: "Launch, menu bar, and app behavior"
        case .advanced: "Diagnostics, sync, and reset actions"
        }
    }

    var symbolName: String {
        switch self {
        case .clipboard: "doc.on.clipboard"
        case .voice: "mic"
        case .downloads: "arrow.down.circle"
        case .folderPreview: "folder"
        case .snippets: "text.quote"
        case .hotkeys: "keyboard"
        case .search: "magnifyingglass"
        case .permissions: "checkmark.shield"
        case .privacy: "hand.raised"
        case .storage: "internaldrive"
        case .general: "gearshape"
        case .advanced: "wrench.and.screwdriver"
        }
    }

    static func legacySelection(_ raw: String?) -> SettingsDestination {
        switch raw {
        case SettingsDestination.clipboard.rawValue, "clipboard":
            .clipboard
        case SettingsDestination.voice.rawValue, "voice", "voiceSpike":
            .voice
        case SettingsDestination.downloads.rawValue, "downloads":
            .downloads
        case SettingsDestination.folderPreview.rawValue, "folderPreview":
            .folderPreview
        case SettingsDestination.snippets.rawValue, "shortcuts":
            .snippets
        case SettingsDestination.hotkeys.rawValue, "hotkeys":
            .hotkeys
        case SettingsDestination.search.rawValue, "search":
            .search
        case SettingsDestination.permissions.rawValue:
            .permissions
        case SettingsDestination.privacy.rawValue, "privacy":
            .privacy
        case SettingsDestination.storage.rawValue, "storage":
            .storage
        case SettingsDestination.general.rawValue, "general", "appearance":
            .general
        case SettingsDestination.advanced.rawValue, "advanced", "sync":
            .advanced
        default:
            .clipboard
        }
    }
}

struct SettingsSidebarGroup: Identifiable {
    let id: String
    let title: String
    let destinations: [SettingsDestination]

    static let all: [SettingsSidebarGroup] = [
        SettingsSidebarGroup(
            id: "product",
            title: "Product",
            destinations: [.clipboard, .voice, .downloads, .folderPreview]
        ),
        SettingsSidebarGroup(
            id: "workflow",
            title: "Workflow",
            destinations: [.snippets, .hotkeys, .search]
        ),
        SettingsSidebarGroup(
            id: "system",
            title: "System",
            destinations: [.permissions, .privacy, .storage, .general, .advanced]
        )
    ]

    static let systemOnly: [SettingsSidebarGroup] = [
        SettingsSidebarGroup(
            id: "system",
            title: "System",
            destinations: [.general, .permissions, .privacy, .storage, .advanced]
        )
    ]
}

enum SettingsExclusionList {
    static func normalizedBundleIDs(_ values: [String]) -> [String] {
        Array(Set(values.map(trimmed).filter { !$0.isEmpty })).sorted()
    }

    static func normalizedRegexPatterns(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values.map(trimmed) where !value.isEmpty && !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
