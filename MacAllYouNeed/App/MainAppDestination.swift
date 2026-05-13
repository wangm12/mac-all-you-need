import Foundation

enum MainAppDestination: String, CaseIterable, Identifiable {
    case dashboard
    case clipboard
    case voice
    case downloads
    case folderPreview
    case snippets
    case settings

    static let storageKey = "main.selectedDestination"

    var id: String { rawValue }

    var contentStyle: MainAppDestinationContentStyle {
        switch self {
        case .settings:
            .embeddedSettings
        case .dashboard, .clipboard, .voice, .downloads, .folderPreview, .snippets:
            .standard
        }
    }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .clipboard: "Clipboard"
        case .voice: "Voice"
        case .downloads: "Downloads"
        case .folderPreview: "Folder Preview"
        case .snippets: "Snippets"
        case .settings: "System"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard: "Status and quick actions"
        case .clipboard: "Recent captured items"
        case .voice: "Dictation controls"
        case .downloads: "Queue and completed items"
        case .folderPreview: "Browse folders and archives"
        case .snippets: "Reusable text entries"
        case .settings: "Global settings and maintenance"
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
        case .settings: "slider.horizontal.3"
        }
    }

    static func storedSelection(_ raw: String?) -> MainAppDestination {
        raw.flatMap(MainAppDestination.init(rawValue:)) ?? .dashboard
    }

    static func load(from defaults: UserDefaults) -> MainAppDestination {
        storedSelection(defaults.string(forKey: storageKey))
    }

    static func persist(_ destination: MainAppDestination, to defaults: UserDefaults) {
        defaults.set(destination.rawValue, forKey: storageKey)
    }
}

enum MainAppDestinationContentStyle: Equatable {
    case standard
    case embeddedSettings
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
