import SwiftUI

struct VoiceDoneStepView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 54))
                .foregroundStyle(.primary)
            Text("All set")
                .font(.largeTitle)
                .bold()
            Text("Press your voice shortcut anywhere on your Mac to dictate.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Advanced features like per-app prompts, dictionary, and AI cleanup live in Voice Settings.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
