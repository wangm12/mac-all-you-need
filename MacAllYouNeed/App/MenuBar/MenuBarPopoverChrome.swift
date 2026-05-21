import SwiftUI

// MARK: - Footer Model

struct CommandCenterFooterModel: Equatable {
    let shortcutText: String?
    let label: String
    let openButtonTitle: String
    let showsCapturePause: Bool
}

// MARK: - Footer Presentation

enum CommandCenterFooterPresentation {
    static func model(
        for tab: AppMenuBarContent.Tab,
        voiceShortcut: String = VoiceActivationSettingsStore.load().shortcut.display
    ) -> CommandCenterFooterModel {
        switch tab {
        case .clipboard:
            CommandCenterFooterModel(
                shortcutText: "⌘⇧V",
                label: "clipboard dock",
                openButtonTitle: "Open Clipboard",
                showsCapturePause: true
            )
        case .voice:
            CommandCenterFooterModel(
                shortcutText: voiceShortcut,
                label: "voice dictation",
                openButtonTitle: "Open Voice",
                showsCapturePause: false
            )
        case .downloads:
            CommandCenterFooterModel(
                shortcutText: nil,
                label: "download queue",
                openButtonTitle: "Open Downloads",
                showsCapturePause: false
            )
        case .snippets:
            CommandCenterFooterModel(
                shortcutText: nil,
                label: "snippet library",
                openButtonTitle: "Open Snippets",
                showsCapturePause: false
            )
        }
    }
}

// MARK: - Tab Bar

struct CommandCenterTabBar: View {
    @Binding var selection: AppMenuBarContent.Tab

    var body: some View {
        FunctionSegmentedTabStrip(
            tabs: Array(AppMenuBarContent.Tab.allCases),
            selection: selection,
            fillsAvailableWidth: true,
            size: .control
        ) { next in
            selection = next
        }
    }
}
