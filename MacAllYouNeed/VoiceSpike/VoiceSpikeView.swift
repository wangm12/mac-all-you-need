import SwiftUI

/// Hidden Settings tab visible only when launched with `--voice-spike`.
struct VoiceSpikeView: View {
    @StateObject private var hotkeyGate = SpikeHotkeyGate()
    @State private var lastResult = "Ready."
    @State private var isRunning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Voice Spike - 5 Gates")
                .font(.title2)
                .bold()

            Group {
                gateButton("Gate 1: Microphone permission + capture") {
                    await SpikeMicGate.run()
                }
                gateButton("Gate 2: Fn / Globe hotkey press/release") {
                    await hotkeyGate.run()
                }
                gateButton("Gate 3: ASR backend smoke test") {
                    await SpikeASRGate.run()
                }
                gateButton("Gate 4: Paste injection (3 apps)") {
                    await SpikePasteGate.runWithUserSwitch()
                }
                gateButton("Gate 5: Benchmark instrumentation") {
                    await SpikeBenchmark.run()
                }
            }
            .buttonStyle(.bordered)
            .disabled(isRunning)

            Divider()
            Text("Last result:")
                .font(.headline)
            ScrollView {
                Text(lastResult)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
            }
        }
        .padding(20)
        .frame(minWidth: 600, minHeight: 480)
    }

    private func gateButton(_ title: String, action: @escaping () async -> String) -> some View {
        Button(title) {
            isRunning = true
            lastResult = "Running \(title)..."
            Task {
                let result = await action()
                await MainActor.run {
                    lastResult = result
                    isRunning = false
                }
            }
        }
    }
}
