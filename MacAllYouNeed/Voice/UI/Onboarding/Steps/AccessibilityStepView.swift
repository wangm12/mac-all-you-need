import ApplicationServices
import AppKit
import FeatureCore
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
                let inline = PermissionGrantPresenter.inlineInstruction(for: .accessibility)
                PermissionCard(
                    title: "Accessibility",
                    reason: "Required so voice output can be inserted into the currently focused app.",
                    state: granted ? .granted : .needed,
                    actionTitle: "Grant"
                ) {
                    grantAccessibility()
                }
                if showsInstruction && !granted {
                    InstructionStrip(
                        text: inline.primaryText,
                        appName: "Mac All You Need",
                        symbol: inline.symbol,
                        secondaryText: inline.secondaryText,
                        dragAppURL: inline.dragAppURL,
                        actionTitle: "Open Settings"
                    ) {
                        PermissionGateProbe.openSettings(for: .accessibility)
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
        .onDisappear {
            PermissionGrantPresenter.dismissFloatingPanel()
        }
        .onReceive(timer) { _ in
            let nowGranted = AXIsProcessTrusted()
            if nowGranted, !granted {
                granted = true
                showsInstruction = false
                PermissionGrantPresenter.dismissFloatingPanel()
                autoAdvance()
            } else {
                granted = nowGranted
            }
        }
    }

    private func grantAccessibility() {
        showsInstruction = true
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if AXIsProcessTrusted() {
            granted = true
            showsInstruction = false
            return
        }
        PermissionGrantPresenter.presentGrant(
            for: .accessibility,
            sourceWindow: NSApp.keyWindow
        ) {
            PermissionGateProbe.openSettings(for: .accessibility)
        }
    }
}
