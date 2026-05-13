import Core
import SwiftUI

struct ClipboardSettingsView: View {
    let controller: AppController
    @AppStorage("clipboardMaxItems", store: AppGroupSettings.defaults) private var maxItems = 10000
    @AppStorage("capture.sound", store: AppGroupSettings.defaults) private var captureSound = false
    @AppStorage("autoPaste.behavior", store: AppGroupSettings.defaults) private var pasteBehavior = "pasteIntoFocused"
    @AppStorage("autoPaste.delayMs", store: AppGroupSettings.defaults) private var pasteDelay = 150
    @State private var blockedApps: [String] = ExcludedAppsStore.load()

    var body: some View {
        MAYNSettingsPage(
            title: "Clipboard",
            subtitle: "Tune capture, history size, and what happens when you pick an item."
        ) {
            MAYNSection(title: "History") {
                MAYNSettingsRow(
                    title: "Maximum items",
                    subtitle: "Upper bound for searchable clipboard history before retention cleanup."
                ) {
                    Stepper("\(maxItems)", value: $maxItems, in: 100...100_000, step: 100)
                        .labelsHidden()
                        .frame(width: 90)
                }
            }

            MAYNSection(title: "Capture") {
                MAYNSettingsRow(
                    title: "Play sound on capture",
                    subtitle: "Audible feedback when a new clipboard item is recorded."
                ) {
                    Toggle("", isOn: $captureSound)
                        .labelsHidden()
                }
                MAYNDivider()
                BundleIDExclusionEditor(bundleIDs: $blockedApps) { ExcludedAppsStore.save($0) }
            }

            MAYNSection(title: "Auto-paste") {
                MAYNSettingsRow(
                    title: "When picking an item",
                    subtitle: "Choose whether the clipboard dock inserts into the focused app or only copies."
                ) {
                    Picker("", selection: $pasteBehavior) {
                        Text("Paste into focused app").tag("pasteIntoFocused")
                        Text("Just copy").tag("copyOnly")
                        Text("Copy, then paste").tag("copyThenPaste")
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }

                if pasteBehavior == "copyThenPaste" {
                    MAYNDivider()
                    MAYNSettingsRow(
                        title: "Paste delay",
                        subtitle: "Wait after copying before sending Command-V."
                    ) {
                        Stepper("\(pasteDelay) ms", value: $pasteDelay, in: 50...2000, step: 50)
                            .labelsHidden()
                            .frame(width: 110)
                    }
                }
            }
        }
    }
}

enum ExcludedAppsStore {
    private static let key = "clipboardExcludedBundleIDs"
    static func load() -> [String] {
        AppGroupSettings.defaults.stringArray(forKey: key) ?? []
    }
    static func save(_ ids: [String]) {
        AppGroupSettings.defaults.set(SettingsExclusionList.normalizedBundleIDs(ids), forKey: key)
    }
}
