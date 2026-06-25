import FeatureCore
import SwiftUI

struct WindowHubOnboardingWizardView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Windows")
                .font(.title2.weight(.semibold))
            Text("Window Hub lists your apps, windows, and tabs as text — no screenshots, no background capture.")
            Text("Grant Accessibility so MAYN can enumerate and switch windows. Use Option+Shift+W to open the hub anywhere.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}
