import Core
import SwiftUI
import CoreFoundation

struct StorageSettingsView: View {
    @State private var maxItems: Int = (AppGroupSettings.defaults.object(forKey: "retention.maxItems") as? Int) ?? 1000
    @State private var maxAgeDays: Int = (AppGroupSettings.defaults.object(forKey: "retention.maxAgeDays") as? Int) ?? 30
    @State private var maxImageMB: Int = (AppGroupSettings.defaults.object(forKey: "retention.maxImageMB") as? Int) ?? 200

    var body: some View {
        Form {
            Section("History size") {
                Stepper(value: $maxItems, in: 100...10_000, step: 100) {
                    Text("Max items: \(maxItems)")
                }
                Picker("Max age", selection: $maxAgeDays) {
                    Text("Forever").tag(0)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("365 days").tag(365)
                }
                Stepper(value: $maxImageMB, in: 0...2_000, step: 50) {
                    Text("Image storage: \(maxImageMB) MB (0 = unlimited)")
                }
            }

            Section("Maintenance") {
                HStack {
                    Button("Clear older than 1 day") {
                        NotificationCenter.default.post(name: .clearClipboardOlderThanRequested, object: 1)
                    }
                    Button("Clear older than 7 days") {
                        NotificationCenter.default.post(name: .clearClipboardOlderThanRequested, object: 7)
                    }
                    Button("Clear older than 30 days") {
                        NotificationCenter.default.post(name: .clearClipboardOlderThanRequested, object: 30)
                    }
                }
            }
        }
        .padding()
        .onChange(of: maxItems) { _, value in
            AppGroupSettings.defaults.set(value, forKey: "retention.maxItems")
            postSettingsChangedDarwin()
        }
        .onChange(of: maxAgeDays) { _, value in
            AppGroupSettings.defaults.set(value, forKey: "retention.maxAgeDays")
            postSettingsChangedDarwin()
        }
        .onChange(of: maxImageMB) { _, value in
            AppGroupSettings.defaults.set(value, forKey: "retention.maxImageMB")
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
