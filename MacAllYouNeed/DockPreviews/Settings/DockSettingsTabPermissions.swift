import ApplicationServices
import SwiftUI

struct DockSettingsTabPermissions: View {
    @Binding var hub: DockHubSettings
    var onSettingsChanged: (() -> Void)?
    @State private var worklogLineCount = 0

    private var settings: DockSettingsHubBindings {
        DockSettingsHubBindings(hub: $hub, onSettingsChanged: onSettingsChanged) {
            DockPreviewWorklog.setEnabled(hub.previews.enableWorklog)
        }
    }

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

            MAYNSection(title: "Diagnostics") {
                MAYNSettingsRow(
                    title: "Worklog",
                    subtitle: "Append hover, show, and dismiss events to worklogs."
                ) {
                    Toggle("", isOn: settings.bool(\.previews.enableWorklog)).labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Reveal worklog", subtitle: worklogSubtitle) {
                    HStack(spacing: 8) {
                        MAYNButton("Reveal") { DockPreviewWorklog.revealInFinder() }
                        MAYNButton("Clear", role: .destructive) {
                            DockPreviewWorklog.clear()
                            refreshWorklogLineCount()
                        }
                    }
                }
            }
        }
        .onAppear {
            DockPreviewWorklog.setEnabled(hub.previews.enableWorklog)
            refreshWorklogLineCount()
        }
    }

    private var worklogSubtitle: String {
        worklogLineCount == 0
            ? "No entries yet today."
            : "\(worklogLineCount) lines in today's worklog."
    }

    private func refreshWorklogLineCount() {
        Task {
            let count = await DockPreviewWorklog.fetchLineCount()
            worklogLineCount = count
        }
    }
}
