import CoreFoundation
import Core
import SwiftUI

struct SearchSettingsView: View {
    @State private var sortMode: String = AppGroupSettings.defaults.string(forKey: "history.sortMode") ?? "recency"
    @State private var fuzzy: Bool = AppGroupSettings.defaults.object(forKey: "search.fuzzy") as? Bool ?? false

    var body: some View {
        MAYNSettingsPage(
            title: "Search",
            subtitle: "Choose how clipboard history is ranked and matched in the dock."
        ) {
            MAYNSection(title: "Ranking") {
                MAYNSettingsRow(
                    title: "Sort history by",
                    subtitle: "Default ordering used when browsing previous clipboard items."
                ) {
                    Picker("", selection: $sortMode) {
                        Text("Recency").tag("recency")
                        Text("Frequency").tag("frequency")
                        Text("Recently used").tag("recentlyUsed")
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
            }

            MAYNSection(title: "Matching") {
                MAYNSettingsRow(
                    title: "Fuzzy search",
                    subtitle: "Allow approximate text matches in clipboard search."
                ) {
                    Toggle("", isOn: $fuzzy)
                        .labelsHidden()
                }
            }
        }
        .onChange(of: sortMode) { _, value in
            AppGroupSettings.defaults.set(value, forKey: "history.sortMode")
            postSettingsChangedDarwin()
        }
        .onChange(of: fuzzy) { _, value in
            AppGroupSettings.defaults.set(value, forKey: "search.fuzzy")
            postSettingsChangedDarwin()
        }
    }

    private func postSettingsChangedDarwin() {
        let name = "com.macallyouneed.settings-changed" as CFString
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name),
            nil,
            nil,
            true
        )
    }
}
