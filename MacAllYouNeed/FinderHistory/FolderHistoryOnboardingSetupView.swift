import SwiftUI

/// Onboarding copy for Finder Folder History (privacy + how recording works).
struct FolderHistoryOnboardingSetupView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(
                "Mac All You Need can remember which folders you open in Finder so you can jump back later from the menu bar or a global shortcut."
            )
            .font(.callout)
            .foregroundStyle(MAYNTheme.muted)
            Text("Only folder paths are stored — never the contents inside those folders.")
                .font(.callout)
                .foregroundStyle(MAYNTheme.muted)
            InstructionStrip(
                text: "After setup, enable Finder Folder History on the Dashboard.",
                symbol: "clock.badge.checkmark",
                secondaryText: "Grant Accessibility if prompted, browse in Finder, then press ⌘⇧H to open your history."
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
