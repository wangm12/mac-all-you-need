import ApplicationServices
import Core
import FeatureCore
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
    case personalization = "profiles"
    case settings

    static let storageKey = "main.voice.selectedTab"
    static let defaultTab = VoiceFunctionTab.dictate

    var title: String {
        switch self {
        case .dictate: "Dictate"
        case .models: "Models"
        case .history: "History"
        case .dictionary: "Dictionary"
        case .personalization: "Personalization"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .dictate: "waveform"
        case .models: "square.stack.3d.down.right"
        case .history: "clock"
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

enum WindowControlPagePresentation {
    static let showsCombinedTabbedPage = false
    static let firstClassDestinations: [MainAppDestination] = [.windowLayouts, .grabAnywhere]
    static let usesSharedSegmentedTabs = false
    static let usesRawSegmentedPicker = false
}

enum WindowControlSettingsPresentation {
    static let sectionTitles = ["Window Layouts", "Layout Shortcuts", "Edge Snap", "Window Grab", "Double-Click Layout", "Shared Ignored Apps", "Shared Diagnostics"]
    static let editsShortcutsInToolSettings = true
    static var customShortcutSeedDescriptor: Platform.HotkeyDescriptor {
        HotkeysSettingsPresentation.customTriggerSeedDescriptor
    }

    static func canEditShortcut(for action: HotkeyAction) -> Bool {
        action.isWindowControlAction
    }

    static func seedDescriptor(for action: HotkeyAction) -> Platform.HotkeyDescriptor {
        action.primaryDefaultDescriptor ?? customShortcutSeedDescriptor
    }
}

struct DashboardToolTileItem: Equatable, Identifiable {
    let destination: MainAppDestination
    let title: String
    let metric: String?
    let detail: String
    let symbolName: String
    let shortcutDisplay: String?
    let statusText: String?
    let statusKind: StatusPill.Kind?
    /// The FeatureID this tile directly manages. nil for non-feature tiles.
    var featureID: FeatureID? = nil
    /// When set, enable/disable on this tile proxies to this FeatureID instead.
    var proxiesFeatureID: FeatureID? = nil

    var id: String { destination.rawValue }
}

enum DashboardToolTilePresentation {
    static func dashboardTiles(
        clipboardCount: Int,
        downloadsQueueCount: Int,
        hotkeys: [HotkeyAction: [Platform.HotkeyDescriptor]] = [:],
        voiceSettings: VoiceActivationSettings = .default,
        windowControlSettings: WindowControlSettings = WindowControlSettingsStore.load(),
        windowControlAXTrusted: Bool = AXIsProcessTrusted()
    ) -> [DashboardToolTileItem] {
        [
            DashboardToolTileItem(
                destination: .clipboard,
                title: "Clipboard",
                metric: "\(clipboardCount)",
                detail: "Capture, search, pin, and paste clipboard history.",
                symbolName: "doc.on.clipboard",
                shortcutDisplay: MainHotkeyPresentation.display(for: .clipboard, in: hotkeys),
                statusText: nil,
                statusKind: nil,
                featureID: .clipboard
            ),
            DashboardToolTileItem(
                destination: .voice,
                title: "Voice",
                metric: nil,
                detail: "Dictate into any app with local speech recognition.",
                symbolName: "mic",
                shortcutDisplay: voiceSettings.shortcut.display,
                statusText: nil,
                statusKind: nil,
                featureID: .voice
            ),
            DashboardToolTileItem(
                destination: .downloads,
                title: "Downloads",
                metric: "\(downloadsQueueCount)",
                detail: "Download media and manage saved files.",
                symbolName: "arrow.down.circle",
                shortcutDisplay: nil,
                statusText: nil,
                statusKind: nil,
                featureID: .downloader
            ),
            DashboardToolTileItem(
                destination: .folderPreview,
                title: "Folder Preview",
                metric: nil,
                detail: "Preview Finder folders and archives.",
                symbolName: "folder.badge.gearshape",
                shortcutDisplay: "Space",
                statusText: nil,
                statusKind: nil,
                featureID: .folderPreview
            ),
            DashboardToolTileItem(
                destination: .snippets,
                title: "Snippets",
                metric: nil,
                detail: "Expand reusable text from this Mac.",
                symbolName: "text.quote",
                shortcutDisplay: nil,
                statusText: nil,
                statusKind: nil,
                // Snippets surfaces the Clipboard feature; there is no separate SnippetsFeatureID.
                featureID: .clipboard,
                proxiesFeatureID: .clipboard
            ),
            DashboardToolTileItem(
                destination: .windowLayouts,
                title: "Window Layouts",
                metric: nil,
                detail: "Arrange, snap, and restore windows.",
                symbolName: "rectangle.3.group",
                shortcutDisplay: nil,
                statusText: windowLayoutsStatusText(settings: windowControlSettings, axTrusted: windowControlAXTrusted),
                statusKind: windowLayoutsStatusKind(settings: windowControlSettings, axTrusted: windowControlAXTrusted),
                featureID: .windowLayouts
            ),
            DashboardToolTileItem(
                destination: .grabAnywhere,
                title: "Window Grab",
                metric: nil,
                detail: "Move windows by holding a modifier and dragging.",
                symbolName: "hand.draw",
                shortcutDisplay: nil,
                statusText: grabAnywhereStatusText(settings: windowControlSettings, axTrusted: windowControlAXTrusted),
                statusKind: grabAnywhereStatusKind(settings: windowControlSettings, axTrusted: windowControlAXTrusted),
                featureID: .windowGrab
            )
        ]
    }

    private static func windowLayoutsStatusText(settings: WindowControlSettings, axTrusted: Bool) -> String? {
        guard settings.enabled else {
            return "Off"
        }
        return axTrusted ? nil : "Needs Accessibility"
    }

    private static func windowLayoutsStatusKind(settings: WindowControlSettings, axTrusted: Bool) -> StatusPill.Kind? {
        guard settings.enabled else {
            return .neutral
        }
        return axTrusted ? nil : .warning
    }

    private static func grabAnywhereStatusText(settings: WindowControlSettings, axTrusted: Bool) -> String? {
        guard settings.enabled, settings.dragAnywhereEnabled else {
            return "Off"
        }
        return axTrusted ? nil : "Needs Accessibility"
    }

    private static func grabAnywhereStatusKind(settings: WindowControlSettings, axTrusted: Bool) -> StatusPill.Kind? {
        guard settings.enabled, settings.dragAnywhereEnabled else {
            return .neutral
        }
        return axTrusted ? nil : .warning
    }
}

enum DashboardVoiceStatusPresentation {
    struct Status: Equatable {
        let text: String
        let kind: StatusPill.Kind
    }

    static func footerStatus(for state: VoiceCoordinator.State) -> Status? {
        switch state {
        case .idle:
            nil
        case .recording:
            Status(text: "Listening", kind: .progress)
        case .transcribing:
            Status(text: "Transcribing", kind: .progress)
        case .pasting:
            Status(text: "Pasting", kind: .progress)
        case .error:
            Status(text: "Error", kind: .warning)
        }
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
        switch destination {
        case .downloads:
            let count = inProgressDownloadCount(in: records)
            return count > 0 ? "\(count)" : nil
        case .dashboard, .clipboard, .voice, .folderPreview, .snippets, .windowLayouts, .grabAnywhere, .settings:
            return nil
        }
    }

    static func inProgressDownloadCount(in records: [DownloadRecord]) -> Int {
        records.filter { $0.state == .running }.count
    }
}

enum MainSidebarDestinationPresentation {
    static let destinationFeatureIDs: [MainAppDestination: FeatureID] = [
        .clipboard: .clipboard,
        .voice: .voice,
        .downloads: .downloader,
        .folderPreview: .folderPreview,
        .snippets: .clipboard,
        .windowLayouts: .windowLayouts,
        .grabAnywhere: .windowGrab,
    ]

    static func featureID(for destination: MainAppDestination) -> FeatureID? {
        destinationFeatureIDs[destination]
    }

    static func renderedDestinations(
        from destinations: [MainAppDestination] = MainAppDestination.primarySidebarDestinations
    ) -> [MainAppDestination] {
        destinations
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
        case .windowLayouts, .grabAnywhere, .dashboard, .settings:
            DashboardToolSettingsRoute(
                destination: destination,
                tabStorageKey: nil,
                tabRawValue: nil
            )
        }
    }
}

enum DashboardToolOpenNavigation {
    static func route(for destination: MainAppDestination) -> DashboardToolSettingsRoute {
        switch destination {
        case .dashboard, .clipboard, .voice, .downloads, .folderPreview, .snippets, .windowLayouts, .grabAnywhere, .settings:
            DashboardToolSettingsRoute(destination: destination, tabStorageKey: nil, tabRawValue: nil)
        }
    }
}

enum MainHotkeyPresentation {
    static func display(
        for action: HotkeyAction,
        in hotkeys: [HotkeyAction: [Platform.HotkeyDescriptor]]
    ) -> String {
        guard let descriptors = hotkeys[action] else {
            return action.primaryDefaultDescriptor?.display ?? "Off"
        }
        return descriptors.first?.display ?? "Off"
    }

}

enum MainToolHeaderShortcutModel {
    static func isEditable(for destination: MainAppDestination) -> Bool {
        false
    }

    static func display(
        for destination: MainAppDestination,
        hotkeys: [HotkeyAction: [Platform.HotkeyDescriptor]],
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
        case .windowLayouts, .grabAnywhere, .dashboard, .settings:
            nil
        }
    }

    static func issue(
        for destination: MainAppDestination,
        hotkeys: [HotkeyAction: [Platform.HotkeyDescriptor]],
        voiceSettings: VoiceActivationSettings,
        systemHotkeys: Set<Platform.HotkeyDescriptor> = SystemHotkeyConflictDetector.currentEnabledSymbolicHotkeys()
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
        case .folderPreview, .snippets, .windowLayouts, .grabAnywhere, .dashboard, .settings:
            return nil
        }
    }

    private static func appHotkeyIssue(
        for action: HotkeyAction,
        hotkeys: [HotkeyAction: [Platform.HotkeyDescriptor]],
        voiceSettings: VoiceActivationSettings,
        systemHotkeys: Set<Platform.HotkeyDescriptor>
    ) -> String? {
        guard let descriptor = hotkeys[action]?.first ?? action.primaryDefaultDescriptor else {
            return nil
        }
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
