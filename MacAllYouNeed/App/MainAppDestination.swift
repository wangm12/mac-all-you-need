import Core
import FeatureCore
import Foundation

enum MainAppDestination: String, CaseIterable, Identifiable {
    case dashboard
    case clipboard
    case voice
    case voiceReminders
    case downloads
    case aiFileOrganizer
    case folderPreview
    case finderHistory
    case snippets
    case windowLayouts
    case grabAnywhere
    case dockPreviews
    case settings

    static let storageKey = "main.selectedDestination"
    static let primarySidebarDestinations: [MainAppDestination] = [
        .dashboard,
        .clipboard,
        .voice,
        .voiceReminders,
        .downloads,
        .aiFileOrganizer,
        .folderPreview,
        .windowLayouts,
        .grabAnywhere,
        .dockPreviews,
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .clipboard: "Clipboard"
        case .voice: "Voice"
        case .voiceReminders: "Voice Reminders"
        case .downloads: "Downloads"
        case .aiFileOrganizer: "AI File Organizer"
        case .folderPreview: "Enhanced Finder"
        case .finderHistory: "Enhanced Finder"
        case .snippets: "Clipboard"
        case .windowLayouts: "Window Layouts"
        case .grabAnywhere: "Window Grab"
        case .dockPreviews: "Dock"
        case .settings: "Settings"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard: "Status and quick actions"
        case .clipboard: "Recent captured items"
        case .voice: "Dictation controls"
        case .voiceReminders: "Spoken tasks saved to Reminders"
        case .downloads: "Queue and completed items"
        case .aiFileOrganizer: "Rename and organize files with AI"
        case .folderPreview: "Quick Look previews, browse folder, and visit history"
        case .finderHistory: "Quick Look previews, browse folder, and visit history"
        case .snippets: "Clipboard history, snippets, and paste behavior"
        case .windowLayouts: "Keyboard shortcuts and edge snapping"
        case .grabAnywhere: "Modifier-drag windows"
        case .dockPreviews: "Dock previews, switcher, Cmd+Tab, lock, and indicator"
        case .settings: "Global app settings"
        }
    }

    var symbolName: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .clipboard: "doc.on.clipboard"
        case .voice: "mic"
        case .voiceReminders: "checklist"
        case .downloads: "arrow.down.circle"
        case .aiFileOrganizer: "sparkles.rectangle.stack"
        case .folderPreview: "folder"
        case .finderHistory: "clock.badge.checkmark"
        case .snippets: "text.quote"
        case .windowLayouts: "rectangle.3.group"
        case .grabAnywhere: "hand.draw"
        case .dockPreviews: "dock.rectangle"
        case .settings: "gearshape"
        }
    }

    static func storedSelection(_ raw: String?) -> MainAppDestination {
        if raw == "windows" {
            return .windowLayouts
        }
        if raw == "windowSwitcher" || raw == "cmdTabEnhancements" || raw == "dockLocking" || raw == "activeAppIndicator" {
            return .dockPreviews
        }
        if raw == "snippets" {
            AppGroupSettings.defaults.set(ClipboardFunctionTab.snippets.rawValue, forKey: ClipboardFunctionTab.storageKey)
            return .clipboard
        }
        if raw == "finderHistory" {
            AppGroupSettings.defaults.set(FolderPreviewFunctionTab.history.rawValue, forKey: FolderPreviewFunctionTab.storageKey)
            return .folderPreview
        }
        return raw.flatMap(MainAppDestination.init(rawValue:)) ?? .dashboard
    }

    static func load(from defaults: UserDefaults) -> MainAppDestination {
        storedSelection(defaults.string(forKey: storageKey))
    }

    static func persist(_ destination: MainAppDestination, to defaults: UserDefaults) {
        defaults.set(destination.rawValue, forKey: storageKey)
    }
}

enum MainStartupSurface: Equatable {
    case appOnboarding
    case featureOnboarding(FeatureID)
    case mainWindow
}

enum MainStartupSurfaceRouter {
    static func surface(
        appOnboardingCompleted: Bool,
        registryOrder: [FeatureID],
        featureEnabled: @escaping (FeatureID) -> Bool
    ) -> MainStartupSurface {
        guard appOnboardingCompleted else { return .appOnboarding }
        if let pending = FeatureOnboardingProgressStore.firstPending(
            in: registryOrder,
            enabled: featureEnabled
        ) {
            return .featureOnboarding(pending)
        }
        return .mainWindow
    }
}
