import Core
import SwiftUI

struct ClipboardSettingsView: View {
    let controller: AppController
    @AppStorage("clipboardMaxItems", store: AppGroupSettings.defaults) private var maxItems = 10000
    @State private var blockedApps: [String] = ExcludedAppsStore.load()
    @State private var newBundleID: String = ""
    var body: some View {
        Form {
            Stepper("Max items: \(maxItems)", value: $maxItems, in: 100...100_000, step: 100)
            Section("Excluded apps") {
                List {
                    ForEach(blockedApps, id: \.self) { Text($0) }
                        .onDelete { offsets in
                            blockedApps.remove(atOffsets: offsets)
                            ExcludedAppsStore.save(blockedApps)
                        }
                }
                .frame(height: 120)
                HStack {
                    TextField("com.example.app", text: $newBundleID)
                    Button("Add") {
                        guard !newBundleID.isEmpty else { return }
                        blockedApps.append(newBundleID)
                        ExcludedAppsStore.save(blockedApps)
                        newBundleID = ""
                    }
                }
            }
        }.padding()
    }
}

enum ExcludedAppsStore {
    private static let key = "clipboardExcludedBundleIDs"
    static func load() -> [String] {
        AppGroupSettings.defaults.stringArray(forKey: key) ?? []
    }
    static func save(_ ids: [String]) {
        AppGroupSettings.defaults.set(Array(Set(ids)).sorted(), forKey: key)
    }
}
