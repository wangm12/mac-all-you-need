import SwiftUI

/// Onboarding setup surface injected by the main app onboarding flow.
/// Mirrors the same recognition-engine guide used by Voice onboarding.
struct VoiceProviderSetupView: View {
    let controller: AppController

    var body: some View {
        VoiceRecognitionSetupGuide(
            controller: controller,
            footerText: "You can refine this later from Voice settings.",
            showsHeaderCopy: true,
            showsLanguageRow: false
        )
    }
}
