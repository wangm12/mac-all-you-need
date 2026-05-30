import Core
import SwiftUI
import WidgetKit

@available(macOS 14, *)
struct RemindersWidget: Widget {
    let kind = "RemindersWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RemindersTimelineProvider()) { entry in
            RemindersWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Reminders")
        .description("See upcoming reminders.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@available(macOS 14, *)
struct ReminderEntry: TimelineEntry {
    let date: Date
    let snapshot: ReminderSnapshot
}

@available(macOS 14, *)
struct RemindersTimelineProvider: TimelineProvider {
    private static let suite = "group.com.macallyouneed.shared"

    func placeholder(in _: Context) -> ReminderEntry {
        ReminderEntry(date: Date(), snapshot: .init())
    }

    func getSnapshot(in _: Context, completion: @escaping (ReminderEntry) -> Void) {
        let defaults = UserDefaults(suiteName: Self.suite)
        let snap = defaults.flatMap { ReminderSnapshotStore.load(from: $0) } ?? .init()
        completion(ReminderEntry(date: Date(), snapshot: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReminderEntry>) -> Void) {
        getSnapshot(in: context) { entry in
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900))))
        }
    }
}

@available(macOS 14, *)
struct RemindersWidgetEntryView: View {
    let entry: ReminderEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Reminders")
                .font(.caption)
                .fontWeight(.semibold)
            if entry.snapshot.recentReminders.isEmpty {
                Text("No reminders")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entry.snapshot.recentReminders.prefix(3)) { r in
                    Text("\u{2022} \(r.title)")
                        .font(.caption)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
