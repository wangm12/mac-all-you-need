import EventKit
import SwiftUI

/// Calendar dock widget (DockDoor `CalendarEmbeddedView` subset).
struct DockCalendarWidgetView: View {
    @State private var events: [String] = []
    @State private var authorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        || EKEventStore.authorizationStatus(for: .event) == .authorized

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today")
                .font(.headline)
            if !authorized {
                Text("Grant Calendar access in System Settings to see events.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if events.isEmpty {
                Text("No upcoming events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(events, id: \.self) { title in
                    HStack(spacing: 8) {
                        Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                        Text(title).lineLimit(1)
                    }
                }
            }
        }
        .frame(minWidth: 240)
        .task { await loadEvents() }
    }

    private func loadEvents() async {
        guard authorized else { return }
        let store = EKEventStore()
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let found = store.events(matching: predicate)
            .prefix(6)
            .map(\.title)
            .map { $0 ?? "Event" }
        await MainActor.run { events = Array(found) }
    }
}
