import Foundation

enum MainAppDestination: String, CaseIterable, Identifiable {
    case dashboard
    case clipboard
    case voice
    case downloads
    case folderPreview
    case snippets
    case windowLayouts
    case grabAnywhere
    case settings

    static let storageKey = "main.selectedDestination"
    static let primarySidebarDestinations: [MainAppDestination] = [
        .dashboard,
        .clipboard,
        .snippets,
        .voice,
        .downloads,
        .folderPreview,
        .windowLayouts,
        .grabAnywhere
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .clipboard: "Clipboard"
        case .voice: "Voice"
        case .downloads: "Downloads"
        case .folderPreview: "Folder Preview"
        case .snippets: "Snippets"
        case .windowLayouts: "Window Layouts"
        case .grabAnywhere: "Window Grab"
        case .settings: "Settings"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard: "Status and quick actions"
        case .clipboard: "Recent captured items"
        case .voice: "Dictation controls"
        case .downloads: "Queue and completed items"
        case .folderPreview: "Finder Quick Look settings"
        case .snippets: "Reusable text entries"
        case .windowLayouts: "Keyboard shortcuts and edge snapping"
        case .grabAnywhere: "Modifier-drag windows"
        case .settings: "Global app settings"
        }
    }

    var symbolName: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .clipboard: "doc.on.clipboard"
        case .voice: "mic"
        case .downloads: "arrow.down.circle"
        case .folderPreview: "folder"
        case .snippets: "text.quote"
        case .windowLayouts: "rectangle.3.group"
        case .grabAnywhere: "hand.draw"
        case .settings: "gearshape"
        }
    }

    static func storedSelection(_ raw: String?) -> MainAppDestination {
        if raw == "windows" {
            return .windowLayouts
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
    case voiceOnboarding
    case mainWindow
}

enum MainStartupSurfaceRouter {
    static func surface(
        appOnboardingCompleted: Bool,
        voiceOnboardingCompleted: Bool
    ) -> MainStartupSurface {
        guard appOnboardingCompleted else { return .appOnboarding }
        guard voiceOnboardingCompleted else { return .voiceOnboarding }
        return .mainWindow
    }
}
