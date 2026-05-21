import ApplicationServices
import SwiftUI

struct VoiceAccessibilityStepView: View {
    let autoAdvance: () -> Void
    @State private var granted = AXIsProcessTrusted()
    @State private var showsInstruction = false
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        SetupTaskPage(
            symbol: "accessibility",
            title: "Type into any app",
            subtitle: "Accessibility lets Mac All You Need paste dictated text into Cursor, Notes, browsers, and other apps."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                let instruction = PermissionInstructionTarget.accessibility.instruction(appName: "Mac All You Need")
                PermissionCard(
                    title: "Accessibility",
                    reason: "Required so voice output can be inserted into the currently focused app.",
                    state: granted ? .granted : .needed,
                    actionTitle: "Open System Settings"
                ) {
                    showsInstruction = true
                    _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                    openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                }
                if showsInstruction && !granted {
                    InstructionStrip(
                        text: instruction.primaryText,
                        appName: "Mac All You Need",
                        symbol: instruction.symbol,
                        secondaryText: instruction.secondaryText,
                        dragAppURL: Bundle.main.bundleURL,
                        actionTitle: "Open Settings"
                    ) {
                        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                    }
                }
                if granted {
                    StatusPill(text: "Ready to paste dictated text", kind: .neutral)
                } else {
                    Text("This step advances automatically once macOS reports the permission as granted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onReceive(timer) { _ in
            let nowGranted = AXIsProcessTrusted()
            if nowGranted, !granted {
                granted = true
                showsInstruction = false
                autoAdvance()
            } else {
                granted = nowGranted
            }
        }
    }
}
