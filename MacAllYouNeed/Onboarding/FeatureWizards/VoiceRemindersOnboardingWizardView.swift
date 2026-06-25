import Core
import Platform
import SwiftUI

struct VoiceRemindersOnboardingWizardView: View {
    let controller: AppController
    @Environment(\.onboardingTryItSucceeded) private var tryItSucceeded
    @State private var statusMessage: String?
    @State private var statusKind: StatusPill.Kind = .neutral

    private var reminderShortcut: String {
        VoiceReminderShortcutSettingsStore.load().shortcut.display
    }

    private let examples: [OnboardingExample] = [
        .init(icon: "mic", input: "remind me to buy milk", output: "Reminder in Inbox"),
        .init(icon: "clock", input: "remind me to call Alex at 3pm", output: "Reminder with due time"),
    ]

    var body: some View {
        FeatureOnboardingPage(
            bullets: [
                "Speak a task and save it directly to Apple Reminders — not into the front app.",
                "Use the reminder shortcut or start any dictation with “remind me to…”."
            ],
            examples: examples,
            tryItSubtitle: "Hold the shortcut, speak a short reminder, then release.",
            tryIt: {
            OnboardingTryItPanel(
                instruction: "Try: “remind me to finish MAYN setup”. Hold \(reminderShortcut), speak, then release.",
                statusMessage: statusMessage,
                statusKind: statusKind,
                showsConfirm: false
            ) {
                HStack(spacing: 10) {
                    ShortcutChip(text: reminderShortcut, height: HotkeyChipPresentation.compactHeight)
                    MAYNButton("Open Reminders", role: .secondary) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Reminders.app"))
                    }
                }
            }
        },
        footnote: "Reminders access was requested during setup. Tune the shortcut in Voice → Settings."
        )
        .onReceive(NotificationCenter.default.publisher(for: .voiceReminderCreated)) { note in
            guard let created = note.object as? CreatedReminder else { return }
            statusMessage = "Saved “\(created.title)” to \(created.listName)."
            statusKind = .success
            OnboardingTryItReporter.markSucceeded(tryItSucceeded)
        }
        .onAppear {
            if controller.voiceCoordinator.lastCreatedReminder != nil {
                let created = controller.voiceCoordinator.lastCreatedReminder!
                statusMessage = "Saved “\(created.title)” to \(created.listName)."
                statusKind = .success
                OnboardingTryItReporter.markSucceeded(tryItSucceeded)
            }
        }
    }
}
