import EventKit
import SwiftUI

private struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarColor: Color
}

/// Calendar dock widget with event times and calendar colors (DockDoor CalendarEmbeddedView parity).
struct DockCalendarWidgetView: View {
    @State private var events: [CalendarEvent] = []
    @State private var authorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        || EKEventStore.authorizationStatus(for: .event) == .authorized

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today")
                .font(.headline)
            if !authorized {
                Text("Grant Calendar access in System Settings to see events.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if events.isEmpty {
                Text("No upcoming events today.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(events) { event in
                    eventRow(event)
                }
            }
        }
        .frame(minWidth: 240)
        .task { await loadEvents() }
    }

    @ViewBuilder
    private func eventRow(_ event: CalendarEvent) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(event.calendarColor)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.callout)
                    .lineLimit(1)
                if event.isAllDay {
                    Text("All day")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(timeFormatter.string(from: event.startDate)) – \(timeFormatter.string(from: event.endDate))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func loadEvents() async {
        guard authorized else { return }
        let store = EKEventStore()
        let filteredIDs = DockHubSettingsStore.load().widgets.filteredCalendarIdentifiers
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let found = store.events(matching: predicate)
            .filter { event in
                guard let cal = event.calendar else { return true }
                return !filteredIDs.contains(cal.calendarIdentifier)
            }
            .prefix(6)
            .compactMap { event -> CalendarEvent? in
                guard let title = event.title else { return nil }
                let nsColor = event.calendar?.color ?? .systemBlue
                let color = Color(nsColor: nsColor)
                return CalendarEvent(
                    id: event.eventIdentifier,
                    title: title,
                    startDate: event.startDate,
                    endDate: event.endDate,
                    isAllDay: event.isAllDay,
                    calendarColor: color
                )
            }
        let result = Array(found)
        await MainActor.run { events = result }
    }
}
