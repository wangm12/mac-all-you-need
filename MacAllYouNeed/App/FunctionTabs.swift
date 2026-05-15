import Core
import Foundation
import Platform

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
    case rules
    case settings

    static let storageKey = "main.clipboard.selectedTab"
    static let defaultTab = ClipboardFunctionTab.history

    var title: String {
        switch self {
        case .history: "History"
        case .rules: "Rules"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .history: "clock"
        case .rules: "shield"
        case .settings: "slider.horizontal.3"
        }
    }
}

enum VoiceFunctionTab: String, FunctionTabDestination {
    case dictate
    case models
    case history
    case dictionary
    case profiles
    case settings

    static let storageKey = "main.voice.selectedTab"
    static let defaultTab = VoiceFunctionTab.dictate

    var title: String {
        switch self {
        case .dictate: "Dictate"
        case .models: "Models"
        case .history: "History"
        case .dictionary: "Dictionary"
        case .profiles: "Profiles"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .dictate: "waveform"
        case .models: "square.stack.3d.down.right"
        case .history: "clock"
        case .dictionary: "text.book.closed"
        case .profiles: "app.badge"
        case .settings: "slider.horizontal.3"
        }
    }
}

enum DownloadsFunctionTab: String, FunctionTabDestination {
    case queue
    case completed
    case settings

    static let storageKey = "main.downloads.selectedTab"
    static let defaultTab = DownloadsFunctionTab.queue

    var title: String {
        switch self {
        case .queue: "Queue"
        case .completed: "Completed"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .queue: "arrow.down.circle"
        case .completed: "checkmark.circle"
        case .settings: "slider.horizontal.3"
        }
    }
}

enum FolderPreviewFunctionTab: String, FunctionTabDestination {
    case settings

    static let storageKey = "main.folderPreview.selectedTab"
    static let defaultTab = FolderPreviewFunctionTab.settings

    var title: String {
        switch self {
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .settings: "slider.horizontal.3"
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
    static let accessibilityRowTitle = "Accessibility"
    static let shortcutRowTitle = "Shortcut"
    static let visibleRowTitles = [accessibilityRowTitle, shortcutRowTitle]
}

struct DashboardToolTileItem: Equatable, Identifiable {
    let destination: MainAppDestination
    let title: String
    let metric: String?
    let detail: String
    let symbolName: String
    let shortcutDisplay: String?

    var id: String { destination.rawValue }
}

enum DashboardToolTilePresentation {
    static func dashboardTiles(
        clipboardCount: Int,
        downloadsQueueCount: Int,
        hotkeys: [HotkeyAction: [HotkeyDescriptor]] = [:],
        voiceSettings: VoiceActivationSettings = .default
    ) -> [DashboardToolTileItem] {
        [
            DashboardToolTileItem(
                destination: .clipboard,
                title: "Clipboard",
                metric: "\(clipboardCount)",
                detail: "Capture, search, pin, and paste clipboard history.",
                symbolName: "doc.on.clipboard",
                shortcutDisplay: MainHotkeyPresentation.display(for: .clipboard, in: hotkeys)
            ),
            DashboardToolTileItem(
                destination: .voice,
                title: "Voice",
                metric: nil,
                detail: "Dictate into any app with local speech recognition.",
                symbolName: "mic",
                shortcutDisplay: voiceSettings.shortcut.display
            ),
            DashboardToolTileItem(
                destination: .downloads,
                title: "Downloads",
                metric: "\(downloadsQueueCount)",
                detail: "Download media and manage saved files.",
                symbolName: "arrow.down.circle",
                shortcutDisplay: nil
            ),
            DashboardToolTileItem(
                destination: .folderPreview,
                title: "Folder Preview",
                metric: nil,
                detail: "Preview Finder folders and archives.",
                symbolName: "folder.badge.gearshape",
                shortcutDisplay: "Space"
            ),
            DashboardToolTileItem(
                destination: .snippets,
                title: "Snippets",
                metric: nil,
                detail: "Expand reusable text from this Mac.",
                symbolName: "text.quote",
                shortcutDisplay: nil
            )
        ]
    }
}

enum DashboardDownloadSummaryPresentation {
    static func activeQueueCount(in records: [DownloadRecord]) -> Int {
        records.filter { DownloadsListFilter.activeQueue.includes($0.state) }.count
    }

    static func isQueueState(_ state: DownloadState) -> Bool {
        DownloadsListFilter.activeQueue.includes(state)
    }
}

enum MainSidebarBadgePresentation {
    static func badgeText(for destination: MainAppDestination, records: [DownloadRecord]) -> String? {
        guard destination == .downloads else { return nil }
        let count = inProgressDownloadCount(in: records)
        return count > 0 ? "\(count)" : nil
    }

    static func inProgressDownloadCount(in records: [DownloadRecord]) -> Int {
        records.filter { $0.state == .running }.count
    }
}

struct DashboardToolSettingsRoute: Equatable {
    let destination: MainAppDestination
    let tabStorageKey: String?
    let tabRawValue: String?
}

enum DashboardToolSettingsNavigation {
    static func route(for destination: MainAppDestination) -> DashboardToolSettingsRoute {
        switch destination {
        case .clipboard:
            DashboardToolSettingsRoute(
                destination: .clipboard,
                tabStorageKey: ClipboardFunctionTab.storageKey,
                tabRawValue: ClipboardFunctionTab.settings.rawValue
            )
        case .voice:
            DashboardToolSettingsRoute(
                destination: .voice,
                tabStorageKey: VoiceFunctionTab.storageKey,
                tabRawValue: VoiceFunctionTab.settings.rawValue
            )
        case .downloads:
            DashboardToolSettingsRoute(
                destination: .downloads,
                tabStorageKey: DownloadsFunctionTab.storageKey,
                tabRawValue: DownloadsFunctionTab.settings.rawValue
            )
        case .folderPreview:
            DashboardToolSettingsRoute(
                destination: .folderPreview,
                tabStorageKey: FolderPreviewFunctionTab.storageKey,
                tabRawValue: FolderPreviewFunctionTab.settings.rawValue
            )
        case .snippets:
            DashboardToolSettingsRoute(
                destination: .snippets,
                tabStorageKey: SnippetsFunctionTab.storageKey,
                tabRawValue: SnippetsFunctionTab.settings.rawValue
            )
        case .dashboard, .settings:
            DashboardToolSettingsRoute(
                destination: destination,
                tabStorageKey: nil,
                tabRawValue: nil
            )
        }
    }
}

enum MainHotkeyPresentation {
    static func display(
        for action: HotkeyAction,
        in hotkeys: [HotkeyAction: [HotkeyDescriptor]]
    ) -> String {
        (hotkeys[action]?.first ?? action.defaultDescriptor).display
    }

}

enum MainToolHeaderShortcutModel {
    static func isEditable(for destination: MainAppDestination) -> Bool {
        false
    }

    static func display(
        for destination: MainAppDestination,
        hotkeys: [HotkeyAction: [HotkeyDescriptor]],
        voiceSettings: VoiceActivationSettings
    ) -> String? {
        switch destination {
        case .clipboard:
            MainHotkeyPresentation.display(for: .clipboard, in: hotkeys)
        case .downloads:
            nil
        case .snippets:
            MainHotkeyPresentation.display(for: .clipboard, in: hotkeys)
        case .voice:
            voiceSettings.shortcut.display
        case .folderPreview:
            "Space"
        case .dashboard, .settings:
            nil
        }
    }

    static func issue(
        for destination: MainAppDestination,
        hotkeys: [HotkeyAction: [HotkeyDescriptor]],
        voiceSettings: VoiceActivationSettings,
        systemHotkeys: Set<HotkeyDescriptor> = SystemHotkeyConflictDetector.currentEnabledSymbolicHotkeys()
    ) -> String? {
        switch destination {
        case .clipboard:
            return appHotkeyIssue(
                for: .clipboard,
                hotkeys: hotkeys,
                voiceSettings: voiceSettings,
                systemHotkeys: systemHotkeys
            )
        case .downloads:
            return nil
        case .voice:
            return HotkeyValidation.issue(
                forVoiceShortcut: voiceSettings.shortcut,
                appHotkeys: hotkeys,
                systemHotkeys: systemHotkeys
            )?.message
        case .folderPreview, .snippets, .dashboard, .settings:
            return nil
        }
    }

    private static func appHotkeyIssue(
        for action: HotkeyAction,
        hotkeys: [HotkeyAction: [HotkeyDescriptor]],
        voiceSettings: VoiceActivationSettings,
        systemHotkeys: Set<HotkeyDescriptor>
    ) -> String? {
        let descriptor = hotkeys[action]?.first ?? action.defaultDescriptor
        return HotkeyValidation.issue(
            forAppHotkey: descriptor,
            action: action,
            index: 0,
            appHotkeys: hotkeys,
            voiceShortcut: voiceSettings.shortcut,
            systemHotkeys: systemHotkeys
        )?.message
    }
}
