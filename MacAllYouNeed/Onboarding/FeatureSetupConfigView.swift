import FeatureCore
import SwiftUI

struct FeatureSetupConfigView: View {
    let descriptor: FeatureDescriptor

    var body: some View {
        SetupTaskPage(
            symbol: "slider.horizontal.3",
            title: "Set up \(descriptor.displayName)",
            subtitle: "Configure how \(descriptor.displayName) should behave. You can change these later from Settings → \(descriptor.displayName)."
        ) {
            if let factory = descriptor.onboardingSetupFactory {
                factory()
            } else {
                Text("No additional setup required.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
    }
}
