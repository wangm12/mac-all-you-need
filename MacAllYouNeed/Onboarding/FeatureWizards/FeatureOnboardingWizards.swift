import FeatureCore
import SwiftUI

// MARK: - Clipboard

struct ClipboardOnboardingWizardView: View {
    let controller: AppController

    var body: some View {
        ClipboardOnboardingHotkeySection(controller: controller)
    }
}
