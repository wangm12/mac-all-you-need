import Core
import Platform
import SwiftUI
import CoreFoundation

struct PrivacySettingsView: View {
    @State private var ignored: [String] = AppGroupSettings.defaults.stringArray(forKey: "clipboardExcludedBundleIDs") ?? []
    @State private var regexes: [String] = AppGroupSettings.defaults.stringArray(forKey: "clipboardRegexBlocklist") ?? []
    @State private var newBundleID = ""
    @State private var newRegex = ""
    @State private var regexError: String?

    var body: some View {
        Form {
            Section("Don't capture from these apps") {
                ForEach(ignored, id: \.self) { bundleID in
                    HStack {
                        Text(bundleID)
                        Spacer()
                        Button("Remove") {
                            ignored.removeAll { $0 == bundleID }
                            save()
                        }
                    }
                }
                HStack {
                    TextField("com.example.app", text: $newBundleID)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let trimmed = newBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        ignored.append(trimmed)
                        newBundleID = ""
                        save()
                    }
                }
            }

            Section("Don't capture text matching") {
                ForEach(regexes, id: \.self) { pattern in
                    HStack {
                        Text(pattern)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Button("Remove") {
                            regexes.removeAll { $0 == pattern }
                            save()
                        }
                    }
                }
                HStack {
                    TextField(#"\d{16}"#, text: $newRegex)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let trimmed = newRegex.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        do {
                            try RegexBlocklist.validate(trimmed)
                            regexes.append(trimmed)
                            newRegex = ""
                            regexError = nil
                            save()
                        } catch {
                            regexError = "Invalid regex: \(error.localizedDescription)"
                        }
                    }
                }
                if let regexError {
                    Text(regexError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .padding()
    }

    private func save() {
        ignored = Array(Set(ignored)).sorted()
        regexes = Array(Set(regexes))
        AppGroupSettings.defaults.set(ignored, forKey: "clipboardExcludedBundleIDs")
        AppGroupSettings.defaults.set(regexes, forKey: "clipboardRegexBlocklist")
        postSettingsChangedDarwin()
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
