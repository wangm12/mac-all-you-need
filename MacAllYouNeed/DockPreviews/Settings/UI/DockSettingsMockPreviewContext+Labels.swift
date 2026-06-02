import Foundation

extension DockSettingsMockPreviewContext {
    var indicatorCaption: String {
        switch self {
        case .dock:
            "Hover a Dock icon to preview its windows"
        case .windowSwitcher:
            "Press Alt ⌥ Tab to cycle windows"
        case .cmdTab:
            "Hold ⌘ while switching apps"
        }
    }
}

struct DockSettingsMockWindow: Equatable {
    let title: String
    let thumbnailLabel: String
    let tint: DockBackgroundStyleFull

    static func samples(for context: DockSettingsMockPreviewContext, tint: DockBackgroundStyleFull) -> [DockSettingsMockWindow] {
        switch context {
        case .dock:
            [
                DockSettingsMockWindow(title: "Notes", thumbnailLabel: "Notes", tint: tint),
                DockSettingsMockWindow(title: "Mail", thumbnailLabel: "Mail", tint: tint),
            ]
        case .windowSwitcher:
            [
                DockSettingsMockWindow(title: "Safari", thumbnailLabel: "Safari", tint: tint),
                DockSettingsMockWindow(title: "Mail", thumbnailLabel: "Mail", tint: tint),
                DockSettingsMockWindow(title: "Notes", thumbnailLabel: "Notes", tint: tint),
            ]
        case .cmdTab:
            [
                DockSettingsMockWindow(title: "Safari — Reading List", thumbnailLabel: "Safari", tint: tint),
                DockSettingsMockWindow(title: "Safari — Start Page", thumbnailLabel: "Safari", tint: tint),
            ]
        }
    }
}
