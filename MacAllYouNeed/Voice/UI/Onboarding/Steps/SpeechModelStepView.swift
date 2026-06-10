import SwiftUI

struct VoiceASRStepView: View {
    let controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose recognition engine")
                .font(.title)
                .bold()
            Text("Use the recommended engine to start quickly. You can choose an exact provider and model later in Voice Settings.")
                .foregroundStyle(.secondary)

            VoiceRecognitionSetupGuide(
                controller: controller,
                footerText: "",
                showsHeaderCopy: false,
                showsLanguageRow: true,
                showsExactSelectionRow: false
            )

            Spacer()
        }
    }
}
