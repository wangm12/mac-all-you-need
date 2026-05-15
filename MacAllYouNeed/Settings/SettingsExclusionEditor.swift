import AppKit
import Platform
import SwiftUI
import UniformTypeIdentifiers

struct BundleIDExclusionEditor: View {
    @Binding var bundleIDs: [String]
    let save: ([String]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(bundleIDs, id: \.self) { bundleID in
                ExcludedAppRow(bundleID: bundleID) {
                    MAYNButton("Remove", role: .destructive, height: HotkeyChipPresentation.compactHeight) {
                        bundleIDs.removeAll { $0 == bundleID }
                        persist()
                    }
                }
                MAYNDivider()
            }

            MAYNSettingsRow(
                title: "Add apps",
                subtitle: "Choose one or more apps. Clipboard content copied from them will not be saved."
            ) {
                MAYNButton(role: .secondary, height: MAYNControlMetrics.controlHeight, action: {
                    chooseApps()
                }) {
                    Label("Choose Apps...", systemImage: "app.badge")
                }
            }
        }
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.title = "Choose Apps to Exclude"
        panel.prompt = "Add Apps"
        panel.message = "Select apps whose clipboard content should never be captured."
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.applicationBundle]

        guard panel.runModal() == .OK else { return }
        bundleIDs.append(contentsOf: SettingsExclusionList.bundleIDs(fromApplicationURLs: panel.urls))
        persist()
    }

    private func persist() {
        let normalized = SettingsExclusionList.normalizedBundleIDs(bundleIDs)
        bundleIDs = normalized
        save(normalized)
    }
}

private struct ExcludedAppRow<Trailing: View>: View {
    let bundleID: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.callout)
                Text(bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var icon: NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 30, height: 30)
        return image
    }

    private var displayName: String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: url)
        else {
            return SettingsExclusionList.friendlyAppName(forBundleID: bundleID)
        }

        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
    }
}

struct RegexExclusionEditor: View {
    @Binding var patterns: [String]
    @Binding var errorMessage: String?
    @State private var draft = ""
    @State private var isShowingCustomPatterns = false
    let save: ([String]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            MAYNSettingsRow(
                title: "Private clipboard markers",
                subtitle: "Password managers and temporary copies marked private are skipped automatically."
            ) {
                StatusPill(text: "Always on", kind: .success)
            }
            MAYNDivider()

            ForEach(SensitiveTextPreset.allCases) { preset in
                MAYNSettingsRow(
                    title: preset.title,
                    subtitle: preset.subtitle
                ) {
                    Toggle("", isOn: presetBinding(preset))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                MAYNDivider()
            }

            DisclosureGroup("Advanced custom rules", isExpanded: $isShowingCustomPatterns) {
                VStack(spacing: 0) {
                    ForEach(customPatterns, id: \.self) { pattern in
                        MAYNSettingsRow(title: "Custom pattern", subtitle: pattern) {
                            MAYNButton("Remove", role: .destructive, height: HotkeyChipPresentation.compactHeight) {
                                removeCustomPattern(pattern)
                            }
                        }
                        MAYNDivider()
                    }

                    MAYNSettingsRow(
                        title: "Add custom pattern",
                        subtitle: "For advanced rules that are not covered above."
                    ) {
                        HStack(spacing: 8) {
                            MAYNTextField(
                                placeholder: #"\d{16}"#,
                                text: $draft,
                                width: 240,
                                font: .system(.caption, design: .monospaced)
                            )
                            MAYNButton("Add", role: .primary) {
                                addCustomPattern()
                            }
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if let errorMessage {
                MAYNDivider()
                MAYNSettingsRow(title: "Pattern error") {
                    StatusPill(text: errorMessage, kind: .danger)
                }
            }
        }
    }

    private var selectedPresetIDs: Set<SensitiveTextPreset> {
        SensitiveTextPreset.selectedIDs(in: patterns)
    }

    private var customPatterns: [String] {
        SensitiveTextPreset.customPatterns(from: patterns)
    }

    private func presetBinding(_ preset: SensitiveTextPreset) -> Binding<Bool> {
        Binding {
            selectedPresetIDs.contains(preset)
        } set: { isSelected in
            var selected = selectedPresetIDs
            if isSelected {
                selected.insert(preset)
            } else {
                selected.remove(preset)
            }
            patterns = SensitiveTextPreset.patterns(
                selectedIDs: selected,
                customPatterns: customPatterns
            )
            errorMessage = nil
            persist()
        }
    }

    private func addCustomPattern() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try RegexBlocklist.validate(trimmed)
            patterns = SensitiveTextPreset.patterns(
                selectedIDs: selectedPresetIDs,
                customPatterns: customPatterns + [trimmed]
            )
            draft = ""
            errorMessage = nil
            persist()
        } catch {
            errorMessage = "Invalid pattern. Check the expression and try again."
        }
    }

    private func removeCustomPattern(_ pattern: String) {
        patterns = SensitiveTextPreset.patterns(
            selectedIDs: selectedPresetIDs,
            customPatterns: customPatterns.filter { $0 != pattern }
        )
        errorMessage = nil
        persist()
    }

    private func persist() {
        let normalized = SettingsExclusionList.normalizedRegexPatterns(patterns)
        patterns = normalized
        save(normalized)
    }
}
