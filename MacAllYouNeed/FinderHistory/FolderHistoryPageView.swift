import Core
import SwiftUI

/// Configuration / guidance page for Finder Folder History, surfaced as the
/// feature's settings tab.
struct FolderHistoryPageView: View {
    var body: some View {
        MAYNSettingsPage(
            title: "Finder Folder History",
            subtitle: "Jump back to folders you've opened in Finder via the hotkey or the menu bar."
        ) {
            MAYNSection(title: "How it works") {
                MAYNSettingsRow(
                    title: "Quick switcher",
                    subtitle: "Press the shortcut anywhere to search recent folders and open one."
                ) {
                    ShortcutChip(text: "⌘⇧H")
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Privacy",
                    subtitle: "Only folder paths are recorded — never the contents of any folder."
                ) {
                    EmptyView()
                }
            }
        }
    }
}
