import ApplicationServices
import SwiftUI

struct DockSettingsTabPermissions: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InstructionStrip(
                text: "Grant permissions so Dock previews, the window switcher, and Cmd+Tab enhancements can see your windows.",
                symbol: "lock.shield",
                secondaryText: "Screen Recording is optional for dock hover but improves thumbnails and live preview."
            )

            MAYNSection(title: "Permissions") {
                MAYNSettingsRow(
                    title: "Accessibility",
                    subtitle: "Required to detect Dock icons and intercept keyboard shortcuts."
                ) {
                    StatusPill(
                        text: AXIsProcessTrusted() ? "Granted" : "Needed",
                        kind: AXIsProcessTrusted() ? .success : .warning
                    )
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Screen Recording",
                    subtitle: "Optional for dock hover titles-only mode; required for thumbnails and live preview."
                ) {
                    StatusPill(
                        text: DockPreviewPermissionGate.screenRecordingGranted() ? "Granted" : "Optional",
                        kind: DockPreviewPermissionGate.screenRecordingGranted() ? .success : .neutral
                    )
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Open Privacy settings",
                    subtitle: "Grant Accessibility or Screen Recording if features do not appear."
                ) {
                    MAYNButton("Open Settings", role: .secondary) {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!
                        )
                    }
                }
            }
        }
    }
}
