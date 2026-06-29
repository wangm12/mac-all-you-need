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
            CommandCenterPageHeader(
                title: "Voice Reminders",
                subtitle: "Speak a task and save it directly to Apple Reminders.",
                actionTitle: "Open Voice",
                onAction: {
                    controller.showMainWindow(destination: .voice)
                }
            )
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
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .voiceReminderCreated)) { note in
            if let created = note.object as? CreatedReminder {
                model.record(created)
            }
        }
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
                CommandCenterSectionLabel(title: "Recent")
                ForEach(model.reminders) { reminder in
                    RemindersPopoverRow(reminder: reminder)
                }
            }
            .padding(.trailing, 8)
            .padding(.bottom, 10)
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

private struct RemindersPopoverRow: View {
    let reminder: CreatedReminder
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MAYNTheme.panelSubtle)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(MAYNTheme.hairline, lineWidth: 1)
                    }
                Image(systemName: "checklist")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MAYNTheme.textSecondary(colorScheme))
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MAYNTheme.textPrimary(colorScheme))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(MAYNTheme.textTertiary(colorScheme))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if !relativeTime.isEmpty {
                Text(relativeTime)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(MAYNTheme.textTertiary(colorScheme))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .maynSelectionBackground(
            isSelected: false,
            isHovering: isHovering,
            shape: .rounded(14)
        )
        .padding(.horizontal, 6)
        .onHover { isHovering = $0 }
    }

    private var subtitle: String {
        if let due = reminder.dueDate {
            return "Saved to \(reminder.listName) · \(RemindersPopoverView.dueLabel(due))"
        }
        return "Saved to \(reminder.listName)"
    }

    private var relativeTime: String {
        CompactTimestamp.format(reminder.createdAt)
    }
}
