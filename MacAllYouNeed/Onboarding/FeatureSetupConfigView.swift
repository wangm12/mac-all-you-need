import FeatureCore
import SwiftUI

struct FeatureSetupConfigView: View {
    let descriptor: FeatureDescriptor

    var body: some View {
        FeatureOnboardingStepView(descriptor: descriptor)
    }
}
