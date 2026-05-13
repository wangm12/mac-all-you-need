import Platform
import SwiftUI

struct BundleIDExclusionEditor: View {
    @Binding var bundleIDs: [String]
    @State private var draft = ""
    let save: ([String]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(bundleIDs, id: \.self) { bundleID in
                MAYNSettingsRow(title: bundleID) {
                    Button("Remove") {
                        bundleIDs.removeAll { $0 == bundleID }
                        persist()
                    }
                    .controlSize(.small)
                }
                MAYNDivider()
            }

            MAYNSettingsRow(
                title: "Add app by bundle ID",
                subtitle: "Use bundle IDs like com.apple.Notes or com.todesktop.230313mzl4w4u92."
            ) {
                HStack(spacing: 8) {
                    TextField("com.example.app", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                    Button("Add") {
                        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        bundleIDs.append(trimmed)
                        draft = ""
                        persist()
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func persist() {
        let normalized = SettingsExclusionList.normalizedBundleIDs(bundleIDs)
        bundleIDs = normalized
        save(normalized)
    }
}

struct RegexExclusionEditor: View {
    @Binding var patterns: [String]
    @Binding var errorMessage: String?
    @State private var draft = ""
    let save: ([String]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(patterns, id: \.self) { pattern in
                MAYNSettingsRow(title: pattern) {
                    Button("Remove") {
                        patterns.removeAll { $0 == pattern }
                        persist()
                    }
                    .controlSize(.small)
                }
                MAYNDivider()
            }

            MAYNSettingsRow(
                title: "Add text pattern",
                subtitle: "Matching clipboard text will not be captured."
            ) {
                HStack(spacing: 8) {
                    TextField(#"\d{16}"#, text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                    Button("Add") {
                        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        do {
                            try RegexBlocklist.validate(trimmed)
                            patterns.append(trimmed)
                            draft = ""
                            errorMessage = nil
                            persist()
                        } catch {
                            errorMessage = "Invalid regex: \(error.localizedDescription)"
                        }
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if let errorMessage {
                MAYNDivider()
                MAYNSettingsRow(title: "Pattern error") {
                    StatusPill(text: errorMessage, kind: .danger)
                }
            }
        }
    }

    private func persist() {
        let normalized = SettingsExclusionList.normalizedRegexPatterns(patterns)
        patterns = normalized
        save(normalized)
    }
}
