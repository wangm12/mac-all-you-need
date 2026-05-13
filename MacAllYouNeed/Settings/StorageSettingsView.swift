import CoreFoundation
import Core
import SwiftUI

struct StorageSettingsView: View {
    @State private var maxItems: Int = (AppGroupSettings.defaults.object(forKey: "retention.maxItems") as? Int) ?? 1000
    @State private var maxAgeDays: Int = (AppGroupSettings.defaults.object(forKey: "retention.maxAgeDays") as? Int) ?? 30
    @State private var maxImageMB: Int = (AppGroupSettings.defaults.object(forKey: "retention.maxImageMB") as? Int) ?? 200

    var body: some View {
        MAYNSettingsPage(
            title: "Storage",
            subtitle: "Set retention limits and run one-time clipboard history cleanup."
        ) {
            MAYNSection(title: "History size") {
                MAYNSettingsRow(
                    title: "Maximum items",
                    subtitle: "Keep clipboard history bounded before retention cleanup runs."
                ) {
                    Stepper("\(maxItems)", value: $maxItems, in: 100...10_000, step: 100)
                        .labelsHidden()
                        .frame(width: 100)
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Maximum age",
                    subtitle: "Old entries are eligible for cleanup after this duration."
                ) {
                    Picker("", selection: $maxAgeDays) {
                        Text("Forever").tag(0)
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                        Text("365 days").tag(365)
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Image storage",
                    subtitle: "Use 0 MB to allow unlimited image blob storage."
                ) {
                    Stepper("\(maxImageMB) MB", value: $maxImageMB, in: 0...2_000, step: 50)
                        .labelsHidden()
                        .frame(width: 110)
                }
            }

            MAYNSection(
                title: "Maintenance",
                subtitle: "Cleanup actions are stacked so labels stay visible in the settings detail pane."
            ) {
                MAYNSettingsRow(
                    title: "Clear clipboard history",
                    subtitle: "Remove entries older than the selected threshold.",
                    minHeight: 112
                ) {
                    VStack(alignment: .trailing, spacing: 8) {
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
        }
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
