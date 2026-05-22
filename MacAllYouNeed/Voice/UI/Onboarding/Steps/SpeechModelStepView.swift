import SwiftUI

struct VoiceASRStepView: View {
    let controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose recognition engine")
                .font(.title)
                .bold()
            Text("Use local recognition by default, or configure exact cloud engines if your workflow needs provider-specific transcription.")
                .foregroundStyle(.secondary)

            VoiceRecognitionSetupGuide(
                controller: controller,
                footerText: "",
                showsHeaderCopy: false,
                showsLanguageRow: true
            )

            Spacer()
        }
    }
}
