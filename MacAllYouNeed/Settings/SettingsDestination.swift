import Foundation

enum SettingsDestination: String, CaseIterable, Identifiable, SegmentedTabDestination {
    case clipboard
    case voice
    case downloads
    case folderPreview
    case snippets
    case hotkeys
    case search
    case permissions
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
        case "privacy":
            .clipboard
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
            destinations: [.permissions, .storage, .general, .advanced]
        )
    ]

    static let systemOnly: [SettingsSidebarGroup] = [
        SettingsSidebarGroup(
            id: "system",
            title: "System",
            destinations: [.general, .permissions, .storage, .advanced]
        )
    ]
}

enum SettingsExclusionList {
    static func bundleIDs(fromApplicationURLs urls: [URL]) -> [String] {
        normalizedBundleIDs(urls.compactMap { Bundle(url: $0)?.bundleIdentifier })
    }

    static func friendlyAppName(forBundleID bundleID: String) -> String {
        if let knownName = knownAppNames[bundleID] {
            return knownName
        }

        let parts = bundleID.split(separator: ".").map(String.init)
        guard let candidate = parts.reversed().first(where: { !genericBundleSuffixes.contains($0.lowercased()) }) else {
            return bundleID
        }
        return prettifiedName(candidate)
    }

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

    private static let knownAppNames = [
        "com.1password.1password": "1Password",
        "com.1password.1password7": "1Password 7",
        "com.1password.1password8": "1Password 8",
        "com.agilebits.onepassword4": "1Password",
        "com.bitwarden.desktop": "Bitwarden",
        "com.dashlane.Dashlane": "Dashlane",
        "com.lastpass.LastPass": "LastPass"
    ]

    private static let genericBundleSuffixes: Set<String> = [
        "app",
        "desktop",
        "mac",
        "macos"
    ]

    private static func prettifiedName(_ value: String) -> String {
        let spaced = value
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        return spaced == spaced.lowercased() ? spaced.capitalized : spaced
    }
}

enum SensitiveTextPreset: String, CaseIterable, Identifiable {
    case creditCards
    case apiKeys
    case privateKeys
    case verificationCodes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .creditCards: "Payment cards"
        case .apiKeys: "API keys and tokens"
        case .privateKeys: "Private keys and certificates"
        case .verificationCodes: "Verification codes"
        }
    }

    var subtitle: String {
        switch self {
        case .creditCards:
            "Skips common 13-19 digit card number formats."
        case .apiKeys:
            "Skips common access tokens, bearer secrets, and service keys."
        case .privateKeys:
            "Skips PEM private keys and certificate blocks."
        case .verificationCodes:
            "Skips short one-time codes when copied with nearby code wording."
        }
    }

    var patterns: [String] {
        switch self {
        case .creditCards:
            [#"\b(?:\d[ -]?){13,19}\b"#]
        case .apiKeys:
            [
                #"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"#,
                #"\bgh[pousr]_[A-Za-z0-9_]{20,255}\b"#,
                #"\b(?:sk-[A-Za-z0-9_-]{20,}|sk-proj-[A-Za-z0-9_-]{20,})\b"#,
                #"(?i)\b(?:api[_-]?key|access[_-]?token|auth[_-]?token|secret[_-]?key)\b\s*[:=]\s*["']?[A-Za-z0-9_\-\.]{16,}"#
            ]
        case .privateKeys:
            [#"-----BEGIN [A-Z ]*(?:PRIVATE KEY|OPENSSH PRIVATE KEY|CERTIFICATE)-----"#]
        case .verificationCodes:
            [#"(?i)\b(?:verification|security|login|one[- ]?time|otp|code)\D{0,24}\b\d{4,8}\b"#]
        }
    }

    static func selectedIDs(in patterns: [String]) -> Set<SensitiveTextPreset> {
        let stored = Set(patterns)
        return Set(allCases.filter { Set($0.patterns).isSubset(of: stored) })
    }

    static func customPatterns(from patterns: [String]) -> [String] {
        let presetPatterns = Set(allCases.flatMap(\.patterns))
        return patterns.filter { !presetPatterns.contains($0) }
    }

    static func patterns(
        selectedIDs: Set<SensitiveTextPreset>,
        customPatterns: [String]
    ) -> [String] {
        SettingsExclusionList.normalizedRegexPatterns(
            allCases.filter { selectedIDs.contains($0) }.flatMap(\.patterns) + customPatterns
        )
    }
}
