import Core
import Foundation

protocol SegmentedTabDestination: CaseIterable, Identifiable, RawRepresentable where RawValue == String {
    var title: String { get }
    var symbolName: String { get }
}

protocol FunctionTabDestination: SegmentedTabDestination {
    static var storageKey: String { get }
    static var defaultTab: Self { get }
}

extension SegmentedTabDestination {
    var id: String { rawValue }
}

extension FunctionTabDestination {
    static func storedSelection(_ raw: String?) -> Self {
        raw.flatMap(Self.init(rawValue:)) ?? defaultTab
    }
}

enum FunctionTabFlowDirection: Equatable {
    case forward
    case backward
}

enum FunctionTabFlow {
    static func direction<Tab: FunctionTabDestination>(
        from oldSelection: Tab,
        to newSelection: Tab,
        in tabs: [Tab]
    ) -> FunctionTabFlowDirection? {
        guard oldSelection.rawValue != newSelection.rawValue,
              let oldIndex = tabs.firstIndex(where: { $0.rawValue == oldSelection.rawValue }),
              let newIndex = tabs.firstIndex(where: { $0.rawValue == newSelection.rawValue })
        else {
            return nil
        }

        return newIndex > oldIndex ? .forward : .backward
    }

    static func contentInsertionOffset(for direction: FunctionTabFlowDirection) -> Double {
        direction == .forward ? 18 : -18
    }
}

enum ClipboardFunctionTab: String, FunctionTabDestination {
    case history
    case snippets
    case settings

    static let storageKey = "main.clipboard.selectedTab"
    static let defaultTab = ClipboardFunctionTab.history

    static func storedSelection(_ raw: String?) -> Self {
        guard let raw else { return defaultTab }
        if raw == "library" { return .snippets }
        if raw == "rules" { return .settings }
        return Self(rawValue: raw) ?? defaultTab
    }

    var title: String {
        switch self {
        case .history: "History"
        case .snippets: "Snippets"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .history: "clock"
        case .snippets: "text.quote"
        case .settings: "slider.horizontal.3"
        }
    }
}

enum VoiceFunctionTab: String, FunctionTabDestination, CaseIterable {
    case history
    case models
    case dictionary
    case personalization = "profiles"
    case settings

    static let storageKey = "main.voice.selectedTab"
    static let defaultTab = VoiceFunctionTab.history

    static func storedSelection(_ raw: String?) -> Self {
        guard let raw else { return defaultTab }
        if raw == "dictate" { return .history }
        return Self(rawValue: raw) ?? defaultTab
    }

    var title: String {
        switch self {
        case .history: "History"
        case .models: "Recognition"
        case .dictionary: "Dictionary"
        case .personalization: "Personalization"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .history: "clock"
        case .models: "square.stack.3d.down.right"
        case .dictionary: "text.book.closed"
        case .personalization: "sparkles"
        case .settings: "slider.horizontal.3"
        }
    }
}

enum VoiceMainPagePresentation {
    static let showsHeaderShortcut = true
    static let headerActionTitle: String? = nil
}

enum DownloadsFunctionTab: String, FunctionTabDestination {
    case downloads
    case settings

    static let storageKey = "main.downloads.selectedTab"
    static let defaultTab = DownloadsFunctionTab.downloads

    static func storedSelection(_ raw: String?) -> Self {
        guard let raw else { return defaultTab }
        if raw == "queue" || raw == "completed" { return .downloads }
        return Self(rawValue: raw) ?? defaultTab
    }

    var title: String {
        switch self {
        case .downloads: "Downloads"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .downloads: "arrow.down.circle"
        case .settings: "slider.horizontal.3"
        }
    }
}

enum WindowLayoutsFunctionTab: String, FunctionTabDestination {
    case shortcuts
    case radial
    case snap
    case apps
    case rules
    case diagnostics

    static let storageKey = "main.windowLayouts.selectedTab"
    static let defaultTab = WindowLayoutsFunctionTab.shortcuts

    var title: String {
        switch self {
        case .shortcuts: "Shortcuts"
        case .radial: "Radial"
        case .snap: "Snap"
        case .apps: "Ignored Apps"
        case .rules: "Rules"
        case .diagnostics: "Diagnostics"
        }
    }

    var symbolName: String {
        switch self {
        case .shortcuts: "command"
        case .radial: "circle.grid.cross"
        case .snap: "square.split.2x2"
        case .apps: "app.badge"
        case .rules: "list.bullet.rectangle"
        case .diagnostics: "stethoscope"
        }
    }
}

enum WindowGrabFunctionTab: String, FunctionTabDestination {
    case gesture
    case apps

    static let storageKey = "main.windowGrab.selectedTab"
    static let defaultTab = WindowGrabFunctionTab.gesture

    var title: String {
        switch self {
        case .gesture: "Gesture"
        case .apps: "Ignored Apps"
        }
    }

    var symbolName: String {
        switch self {
        case .gesture: "hand.draw"
        case .apps: "app.badge"
        }
    }
}

enum FolderPreviewFunctionTab: String, FunctionTabDestination {
    case settings
    case history

    static let storageKey = "main.folderPreview.selectedTab"
    static let defaultTab = FolderPreviewFunctionTab.settings

    static func storedSelection(_ raw: String?) -> Self {
        guard let raw else { return defaultTab }
        return Self(rawValue: raw) ?? defaultTab
    }

    var title: String {
        switch self {
        case .settings: "Preview"
        case .history: "History"
        }
    }

    var symbolName: String {
        switch self {
        case .settings: "folder"
        case .history: "clock.badge.checkmark"
        }
    }
}

enum FolderPreviewMainPagePresentation {
    static let settingsSectionTitle = "Preview settings"
    static let visibleSectionTitles = [settingsSectionTitle]
    static let settingsRowTitles = ["Include hidden files", "Cascade folders", "Maximum entries"]
}

enum SnippetsFunctionTab: String, FunctionTabDestination {
    case library
    case settings

    static let storageKey = "main.snippets.selectedTab"
    static let defaultTab = SnippetsFunctionTab.library

    var title: String {
        switch self {
        case .library: "Library"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .library: "text.quote"
        case .settings: "slider.horizontal.3"
        }
    }
}

enum SnippetsSettingsPresentation {
    static let expansionModeRowTitle = "Expansion mode"
    static let accessibilityRowTitle = "Accessibility"
    static let shortcutRowTitle = "Shortcut"
    static let visibleRowTitles = [expansionModeRowTitle, accessibilityRowTitle, shortcutRowTitle]

    static func expansionModeSubtitle(for mode: SnippetExpansionMode) -> String {
        switch mode {
        case .autoExpand:
            "Expand as soon as a trigger is followed by whitespace."
        case .confirmWithTab:
            "Type the trigger, then press Tab to expand it."
        case .disabled:
            "Keep typed triggers literal; paste snippets from the app instead."
        }
    }
}

enum SnippetsListPresentation {
    static let usesLocalDockModelSource = true
    static let menuRowsShowBodyPreview = true
    static let menuRowsKeepTriggerVisible = true

    static func menuBodyPreview(for snippet: Snippet) -> String {
        snippet.body
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension SnippetExpansionMode: SegmentedTabDestination {
    var title: String {
        switch self {
        case .autoExpand: "Auto"
        case .confirmWithTab: "Tab"
        case .disabled: "Off"
        }
    }

    var symbolName: String {
        switch self {
        case .autoExpand: "bolt.fill"
        case .confirmWithTab: "keyboard"
        case .disabled: "pause.circle"
        }
    }
}
