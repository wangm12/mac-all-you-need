import Core
import SwiftUI

struct VoiceRemindersPage: View {
    let controller: AppController

    var body: some View {
        MAYNSettingsPage(
            title: "Voice Reminders",
            subtitle: "Speak a task and save it directly to Apple Reminders."
        ) {
            MAYNSection(title: "How it works") {
                MAYNSettingsRow(
                    title: "Speak a reminder",
                    subtitle: "Start a dictation that begins with \u{201C}remind me to\u{2026}\u{201D} or press the reminder shortcut. Your speech is cleaned up and saved directly to Apple Reminders."
                ) {
                    EmptyView()
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Reminders permission",
                    subtitle: "Voice Reminders requires Reminders access. Open System Settings \u{2192} Privacy & Security \u{2192} Reminders and enable Mac All You Need."
                ) {
                    MAYNButton("Open Settings", role: .secondary) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!)
                    }
                }
            }
            MAYNSection(title: "Shortcut") {
                MAYNSettingsRow(
                    title: "Reminder shortcut",
                    subtitle: "Hold this shortcut, speak your reminder, then release to save it."
                ) {
                    ShortcutChip(text: "\u{2318}\u{21E7}R", height: HotkeyChipPresentation.compactHeight)
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Trigger phrase",
                    subtitle: "Start any dictation with \u{201C}remind me to\u{2026}\u{201D} to route it to Reminders automatically."
                ) {
                    EmptyView()
                }
            }
        }
    }
}
