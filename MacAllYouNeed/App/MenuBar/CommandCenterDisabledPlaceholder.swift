import SwiftUI

struct CommandCenterDisabledPlaceholder: View {
    let featureName: String

    var body: some View {
        VStack(spacing: 8) {
            Text("\(featureName) is disabled")
                .font(.headline)
            Text("Enable it on the Dashboard to use this tab.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
