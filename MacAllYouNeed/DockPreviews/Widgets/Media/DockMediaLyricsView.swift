import SwiftUI

struct DockMediaLyricsView: View {
    let bundleIdentifier: String?
    @State private var line: String?

    var body: some View {
        Group {
            if let line, !line.isEmpty {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .task(id: bundleIdentifier) {
            line = await DockMediaLyricsService.fetchLyrics(bundleIdentifier: bundleIdentifier)
        }
    }
}
