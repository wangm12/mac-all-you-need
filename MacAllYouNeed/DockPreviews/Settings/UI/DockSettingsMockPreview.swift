import SwiftUI

enum DockSettingsMockPreviewContext {
    case dock
    case windowSwitcher
    case cmdTab

    var presentationMode: DockPreviewPresentationMode {
        switch self {
        case .dock: .dockHover
        case .windowSwitcher: .windowSwitcher
        case .cmdTab: .cmdTab
        }
    }
}

/// Live settings preview that animates selection and reflects current appearance choices.
struct DockSettingsMockPreview: View {
    @Binding var hub: DockHubSettings
    let context: DockSettingsMockPreviewContext

    private var refreshSignature: String {
        DockSettingsPreviewBuilder.signature(hub: hub, context: context)
    }

    private var snapshot: DockSettingsPreviewSnapshot {
        DockSettingsPreviewBuilder.snapshot(hub: hub, context: context)
    }

    var body: some View {
        DockSettingsAnimatedPreview(snapshot: snapshot, context: context)
            .padding(.vertical, 20)
            .preferredColorScheme(DockSettingsPreviewBuilder.preferredColorScheme(for: hub.appearance.appAppearanceMode))
            .id(refreshSignature)
    }
}
