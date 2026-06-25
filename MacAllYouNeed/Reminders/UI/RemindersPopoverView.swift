import Combine
import Core
import EventKit
import SwiftUI

/// Command Center Reminders tab. Shows reminders created via voice, or a
/// permission prompt when EventKit access has not been granted.
struct RemindersPopoverView: View {
    let controller: AppController
    @State private var model: RemindersListModel

    init(controller: AppController) {
        self.controller = controller
        _model = State(initialValue: RemindersListModel(service: controller.remindersService))
    }

    var body: some View {
        VStack(spacing: 0) {
            popoverHeader
            Group {
                if model.authorizationStatus != .fullAccess {
                    permissionView
                } else if model.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.reminders.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checklist")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("No reminders yet")
                            .font(.headline)
                        StatusPill(text: "Ready", kind: .neutral)
                        Text("Say \u{201C}remind me to\u{2026}\u{201D} or use the reminder shortcut.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    remindersList
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MAYNTheme.window)
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .voiceReminderCreated)) { note in
            if let created = note.object as? CreatedReminder {
                model.record(created)
            }
        }
    }

    private var popoverHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reminders")
                    .font(.headline.weight(.semibold))
                Text("Voice-created reminders live here. Open the full Voice page for setup, dictation, and reminders flow.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            MAYNButton("Open Voice", role: .primary, height: HotkeyChipPresentation.compactHeight) {
                controller.showMainWindow(destination: .voice)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(MAYNTheme.panel)
    }

    @ViewBuilder
    private var permissionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Reminders Access")
                .font(.headline)
            StatusPill(text: "Needs access", kind: .warning)
            Text("Allow access to save spoken reminders to Apple Reminders.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            MAYNButton("Allow Access", role: .primary) {
                Task { await model.requestAccess() }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var remindersList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.reminders) { reminder in
                    HStack(spacing: 10) {
                        Image(systemName: "circle")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reminder.title)
                            if let due = reminder.dueDate {
                                Text(Self.dueLabel(due))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(reminder.listName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    static func dueLabel(_ due: ReminderDueDate) -> String {
        let base = String(format: "%04d-%02d-%02d", due.year, due.month, due.day)
        if let hour = due.hour {
            return base + String(format: " %02d:%02d", hour, due.minute ?? 0)
        }
        return base
    }
}
