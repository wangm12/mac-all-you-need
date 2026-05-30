import Core
import FeatureCore
import SwiftUI

enum FinderHistoryDescriptor {
    static func descriptor() -> FeatureDescriptor {
        FeatureDescriptor(
            id: .folderHistory,
            displayName: "Finder Folder History",
            icon: "folder.badge.clock",
            summary: "Jump back to recently visited folders instantly.",
            detailDescription: "Records the folders you open in Finder via accessibility observation and lets you "
                + "reopen them from a hotkey quick-switcher or the menu bar. Only folder paths are stored — never "
                + "folder contents. Disabled by default; recording starts only after you opt in.",
            requiredPermissions: [.accessibility],
            activator: NoopFeatureActivator(),
            settingsTabFactory: { AnyView(FolderHistoryPageView()) },
            menuBarItemFactory: {
                AnyView(FolderHistoryMenuBarMount())
            }
        )
    }
}

/// Resolves the shared store at view-build time so the menu-bar factory (built
/// from the static registry) renders against the live database.
private struct FolderHistoryMenuBarMount: View {
    var body: some View {
        if let store = FolderHistoryStoreLocator.shared() {
            FolderHistoryMenuBarView(store: store)
        } else {
            EmptyView()
        }
    }
}
