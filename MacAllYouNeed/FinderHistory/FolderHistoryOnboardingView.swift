import SwiftUI

/// Consent step shown before enabling Finder Folder History. The feature is
/// disabled by default and only begins recording after the user opts in here.
struct FolderHistoryOnboardingView: View {
    let onConsent: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 48))
                .foregroundStyle(MAYNTheme.muted)
            Text("Track Finder Navigation?")
                .font(.title2)
                .fontWeight(.semibold)
            Text(
                "Mac All You Need will note which folders you open in Finder so you can jump back quickly. "
                    + "Only the folder path is recorded — never the contents of any folder."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(MAYNTheme.muted)
            HStack(spacing: 12) {
                MAYNButton("Not Now", role: .secondary, action: onDecline)
                MAYNButton("Enable", role: .primary, action: onConsent)
            }
        }
        .padding(32)
        .frame(width: 400)
    }
}
