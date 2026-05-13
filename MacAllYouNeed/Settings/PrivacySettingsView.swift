import CoreFoundation
import Core
import Platform
import SwiftUI

struct PrivacySettingsView: View {
    @State private var ignored: [String] = AppGroupSettings.defaults.stringArray(forKey: "clipboardExcludedBundleIDs") ?? []
    @State private var regexes: [String] = AppGroupSettings.defaults.stringArray(forKey: "clipboardRegexBlocklist") ?? []
    @State private var regexError: String?

    var body: some View {
        MAYNSettingsPage(
            title: "Privacy",
            subtitle: "Decide what never enters local history. Clipboard content stays on this Mac by default."
        ) {
            MAYNSection(
                title: "Local capture",
                subtitle: "These safeguards run before data is written to the App Group database."
            ) {
                MAYNSettingsRow(
                    title: "Your data stays private",
                    subtitle: "Clipboard history is local and encrypted. Excluded apps and text patterns are skipped before storage."
                ) {
                    StatusPill(text: "Local only", kind: .success)
                }
            }

            MAYNSection(title: "Do not capture from these apps") {
                BundleIDExclusionEditor(bundleIDs: $ignored) { values in
                    ignored = values
                    save()
                }
            }

            MAYNSection(title: "Do not capture matching text") {
                RegexExclusionEditor(patterns: $regexes, errorMessage: $regexError) { values in
                    regexes = values
                    save()
                }
            }
        }
    }

    private func save() {
        ignored = SettingsExclusionList.normalizedBundleIDs(ignored)
        regexes = SettingsExclusionList.normalizedRegexPatterns(regexes)
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
