import Core
import SwiftUI
import CoreFoundation

struct SearchSettingsView: View {
    @State private var sortMode: String = AppGroupSettings.defaults.string(forKey: "history.sortMode") ?? "recency"
    @State private var fuzzy: Bool = AppGroupSettings.defaults.object(forKey: "search.fuzzy") as? Bool ?? false

    var body: some View {
        Form {
            Picker("Sort history by", selection: $sortMode) {
                Text("Recency").tag("recency")
                Text("Frequency").tag("frequency")
                Text("Recently used").tag("recentlyUsed")
            }
            Toggle("Fuzzy search", isOn: $fuzzy)
        }
        .padding()
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
