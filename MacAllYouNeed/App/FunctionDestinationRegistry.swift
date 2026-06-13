// swiftlint:disable file_length
import ApplicationServices
import Core
import FeatureCore
import Foundation
import Platform
import SwiftUI

enum WindowControlPagePresentation {
    static let showsCombinedTabbedPage = false
    static let firstClassDestinations: [MainAppDestination] = [.windowLayouts, .grabAnywhere]
    static let usesSharedSegmentedTabs = false
    static let usesRawSegmentedPicker = false
}

enum WindowControlSettingsPresentation {
    static let sectionTitles = [
        "Window Layouts", "Layout Shortcuts", "Edge Snap",
        "Window Grab", "Shared Ignored Apps", "Shared Diagnostics"
    ]
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

    /// True when the user tapped + but the shortcut is not saved in the hotkey map yet.
    static func isPendingShortcutOnly(
        storedDescriptors: [Platform.HotkeyDescriptor],
        pendingDescriptor: Platform.HotkeyDescriptor?
    ) -> Bool {
        pendingDescriptor != nil && storedDescriptors.isEmpty
    }

    /// Baseline for the Reset button enabled/disabled state in `HotkeyRecorderControl`.
    static func resetBaselineDescriptor(
        for action: HotkeyAction,
        current: Platform.HotkeyDescriptor,
        isPendingOnly: Bool
    ) -> Platform.HotkeyDescriptor? {
        if let primary = action.primaryDefaultDescriptor {
            return primary
        }
        if isPendingOnly {
            return seedDescriptor(for: action)
        }
        return current
    }

    static func resetHelp(for action: HotkeyAction, isPendingOnly: Bool) -> String {
        if isPendingOnly {
            return action.primaryDefaultDescriptor == nil
                ? "Revert to starter shortcut"
                : "Use default shortcut"
        }
        return action.primaryDefaultDescriptor == nil
            ? "Turn off shortcut"
            : "Reset to default"
    }

    static func closeHelp(isPendingOnly: Bool) -> String {
        isPendingOnly ? "Cancel" : "Turn off shortcut"
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
    var featureID: FeatureID?
    /// When set, enable/disable on this tile proxies to this FeatureID instead.
    var proxiesFeatureID: FeatureID?

    var id: String { title }
}

enum DashboardToolTilePresentation {
    /// Base (static) tile items derived from the feature registry. These carry the descriptor's
    /// displayName, icon, and summary. Runtime data (metrics, shortcuts, status) is layered on
    /// by `dashboardTiles(...)` below.
    static func baseTiles(registry: FeatureRegistry) -> [DashboardToolTileItem] {
        // Ordered list of (destination, featureID) pairs that appear on the dashboard.
        // Destinations without a featureID (dashboard, settings) are excluded here.
        // The Snippets tile proxies Clipboard's featureID — handled as a special case below.
        let orderedDestinations: [(MainAppDestination, FeatureID)] = [
            (.clipboard, .clipboard),
            (.snippets, .clipboard), // proxy tile
            (.voice, .voice),
            (.voiceReminders, .voiceReminders),
            (.downloads, .downloader),
            (.folderPreview, .folderPreview),
            (.finderHistory, .folderHistory),
            (.aiFileOrganizer, .aiFileOrganizer),
            (.windowLayouts, .windowLayouts),
            (.grabAnywhere, .windowGrab),
            (.dockPreviews, .dockPreviews)
        ]

        return orderedDestinations.compactMap { (destination, featureID) in
            guard let descriptor = registry.descriptor(for: featureID) else { return nil }
            let isProxy = destination == .snippets
            return DashboardToolTileItem(
                destination: destination,
                title: descriptor.displayName,
                metric: nil,
                detail: descriptor.summary,
                symbolName: descriptor.icon,
                shortcutDisplay: nil,
                statusText: nil,
                statusKind: nil,
                featureID: featureID,
                proxiesFeatureID: isProxy ? featureID : nil
            )
        }
    }

    // swiftlint:disable:next function_body_length
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
                destination: .voiceReminders,
                title: "Voice Reminders",
                metric: nil,
                detail: "Speak a task and save it directly to Apple Reminders.",
                symbolName: "checklist",
                shortcutDisplay: nil,
                statusText: nil,
                statusKind: nil,
                featureID: .voiceReminders
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
                destination: .finderHistory,
                title: "Finder Folder History",
                metric: nil,
                detail: "Jump back to recently visited Finder folders via hotkey.",
                symbolName: "clock.badge.checkmark",
                shortcutDisplay: nil,
                statusText: nil,
                statusKind: nil,
                featureID: .folderHistory
            ),
            DashboardToolTileItem(
                destination: .aiFileOrganizer,
                title: "AI File Organizer",
                metric: nil,
                detail: "Rename and re-file messy folders using on-device content extraction.",
                symbolName: "sparkles.rectangle.stack",
                shortcutDisplay: nil,
                statusText: nil,
                statusKind: nil,
                featureID: .aiFileOrganizer
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
            ),
            DashboardToolTileItem(
                destination: .dockPreviews,
                title: "Dock Hover Previews",
                metric: nil,
                detail: "See window thumbnails when hovering an app's Dock icon.",
                symbolName: "dock.rectangle",
                shortcutDisplay: nil,
                statusText: nil,
                statusKind: nil,
                featureID: .dockPreviews
            )
        ]
    }

    /// Primary dashboard tile for a feature (excludes proxy tiles such as Snippets → Clipboard).
    static func primaryTile(for featureID: FeatureID) -> DashboardToolTileItem? {
        dashboardTiles(clipboardCount: 0, downloadsQueueCount: 0)
            .first { $0.featureID == featureID && $0.proxiesFeatureID == nil }
    }

    static func accent(for destination: MainAppDestination) -> Color {
        switch destination {
        case .clipboard:
            Color(red: 0.10, green: 0.42, blue: 0.92)
        case .voice:
            Color(red: 0.64, green: 0.22, blue: 0.88)
        case .downloads:
            Color(red: 0.02, green: 0.58, blue: 0.42)
        case .folderPreview:
            Color(red: 0.86, green: 0.46, blue: 0.12)
        case .snippets:
            Color(red: 0.82, green: 0.18, blue: 0.36)
        case .windowLayouts:
            Color(red: 0.20, green: 0.48, blue: 0.72)
        case .grabAnywhere:
            Color(red: 0.24, green: 0.46, blue: 0.36)
        case .dockPreviews:
            Color(red: 0.10, green: 0.42, blue: 0.92)
        case .finderHistory:
            Color(red: 0.86, green: 0.46, blue: 0.12)
        case .aiFileOrganizer:
            Color(red: 0.02, green: 0.58, blue: 0.42)
        case .dashboard, .settings, .voiceReminders:
            .secondary
        }
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
        case .dashboard, .clipboard, .voice, .voiceReminders, .folderPreview, .finderHistory,
             .snippets, .windowLayouts, .grabAnywhere, .dockPreviews, .aiFileOrganizer, .settings:
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
        .voiceReminders: .voiceReminders,
        .downloads: .downloader,
        .aiFileOrganizer: .aiFileOrganizer,
        .folderPreview: .folderPreview,
        .finderHistory: .folderHistory,
        .snippets: .clipboard,
        .windowLayouts: .windowLayouts,
        .grabAnywhere: .windowGrab,
        .dockPreviews: .dockPreviews
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
        case .windowLayouts, .grabAnywhere, .dashboard, .settings,
             .voiceReminders, .finderHistory, .aiFileOrganizer, .dockPreviews:
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
        case .dashboard, .clipboard, .voice, .voiceReminders, .downloads, .aiFileOrganizer,
             .folderPreview, .finderHistory, .snippets, .windowLayouts, .grabAnywhere, .dockPreviews, .settings:
            DashboardToolSettingsRoute(destination: destination, tabStorageKey: nil, tabRawValue: nil)
        }
    }
}

enum VoiceModelsNavigation {
    static func route() -> DashboardToolSettingsRoute {
        DashboardToolSettingsRoute(
            destination: .voice,
            tabStorageKey: VoiceFunctionTab.storageKey,
            tabRawValue: VoiceFunctionTab.models.rawValue
        )
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
            nil
        case .voice:
            voiceSettings.shortcut.display
        case .folderPreview:
            "Space"
        case .windowLayouts, .grabAnywhere, .dashboard, .settings,
             .voiceReminders, .finderHistory, .aiFileOrganizer, .dockPreviews:
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
        case .folderPreview, .snippets, .windowLayouts, .grabAnywhere, .dashboard, .settings,
             .voiceReminders, .finderHistory, .aiFileOrganizer, .dockPreviews:
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
