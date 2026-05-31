import Core
import CoreFoundation
import SwiftUI

// Internal (not private) so ClipboardSmartTextSettingsSection can reference it in @Binding.
enum LinkModeTab: String, SegmentedTabDestination, CaseIterable {
    case off, manual, auto

    var title: String {
        switch self {
        case .off: "Off"
        case .manual: "Manual"
        case .auto: "Auto"
        }
    }

    var symbolName: String {
        switch self {
        case .off: "link.badge.plus"
        case .manual: "hand.tap"
        case .auto: "wand.and.stars"
        }
    }
}

// MARK: - Sheet

/// Presented as a sheet from SmartTextEnableSection.
/// All state is held locally. Save writes to UserDefaults + notifies the daemon.
/// Close discards changes.
struct ClipboardSmartTextSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    // Local draft state — only flushed to UserDefaults on Save.
    @State private var calculation: Bool
    @State private var detection: Bool
    @State private var ocr: Bool
    @State private var sensitive: Bool
    @State private var semantic: Bool
    @State private var linkMode: LinkModeTab

    init() {
        _calculation = State(initialValue: SmartTextSettings.calculationEnabled())
        _detection   = State(initialValue: SmartTextSettings.detectionEnabled())
        _ocr         = State(initialValue: SmartTextSettings.ocrEnabled())
        _sensitive   = State(initialValue: SmartTextSettings.sensitiveEnabled())
        _semantic    = State(initialValue: SmartTextSettings.semanticEnabled())
        _linkMode    = State(initialValue: LinkModeTab(rawValue: SmartTextSettings.linkMode().rawValue) ?? .auto)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Smart Text")
                        .font(.title3.weight(.semibold))
                    Text("On-device intelligence over your clipboard.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                MAYNButton("Close") { dismiss() }
                MAYNButton("Save", role: .primary) { save(); dismiss() }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                ClipboardSmartTextSettingsSection(
                    calculation: $calculation,
                    detection: $detection,
                    ocr: $ocr,
                    sensitive: $sensitive,
                    semantic: $semantic,
                    linkMode: $linkMode
                )
                .padding(24)
            }
            .scrollIndicators(.never)
        }
        .frame(width: 540, height: 520)
        .background(MAYNTheme.window)
    }

    private func save() {
        SmartTextSettings.setCalculationEnabled(calculation)
        SmartTextSettings.setDetectionEnabled(detection)
        SmartTextSettings.setOCREnabled(ocr)
        SmartTextSettings.setSensitiveEnabled(sensitive)
        SmartTextSettings.setSemanticEnabled(semantic)
        SmartTextSettings.setLinkMode(SmartTextSettings.LinkMode(rawValue: linkMode.rawValue) ?? .auto)
        let name = "com.macallyouneed.settings-changed" as CFString
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name), nil, nil, true
        )
    }
}

// MARK: - Section (pure form, no side effects)

/// Accepts bindings from the parent sheet. No immediate UserDefaults writes.
struct ClipboardSmartTextSettingsSection: View {
    @Binding var calculation: Bool
    @Binding var detection: Bool
    @Binding var ocr: Bool
    @Binding var sensitive: Bool
    @Binding var semantic: Bool
    @Binding var linkMode: LinkModeTab

    var body: some View {
        Group {
            MAYNSection(title: "Detection") {
                MAYNSettingsRow(
                    title: "Inline calculation",
                    subtitle: "Show the result when a clip is a math expression."
                ) {
                    Toggle("", isOn: $calculation).labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Smart detection",
                    subtitle: "Detect emails, links, phone numbers, colors, JWTs, and code."
                ) {
                    Toggle("", isOn: $detection).labelsHidden()
                }
            }

            MAYNSection(title: "Links") {
                MAYNSettingsRow(
                    title: "Link cleaner",
                    subtitle: "Strip tracking parameters (utm_, fbclid, …) from copied URLs."
                ) {
                    FunctionSegmentedTabStrip(
                        tabs: Array(LinkModeTab.allCases),
                        selection: linkMode,
                        fillsAvailableWidth: false,
                        size: .control
                    ) { linkMode = $0 }
                }
            }

            MAYNSection(title: "Images") {
                MAYNSettingsRow(
                    title: "Image text recognition (OCR)",
                    subtitle: "Index text inside copied images so it's searchable."
                ) {
                    Toggle("", isOn: $ocr).labelsHidden()
                }
            }

            MAYNSection(title: "Search") {
                MAYNSettingsRow(
                    title: "Semantic ranking",
                    subtitle: "Blend meaning-based matches into clipboard search results."
                ) {
                    Toggle("", isOn: $semantic).labelsHidden()
                }
            }

            MAYNSection(title: "Privacy") {
                MAYNSettingsRow(
                    title: "Sensitive content filter",
                    subtitle: "Skip capturing payment cards and clips from password managers."
                ) {
                    Toggle("", isOn: $sensitive).labelsHidden()
                }
            }

            MAYNSection(title: "Keyboard shortcuts") {
                MAYNSettingsRow(
                    title: "Copy Smart Text",
                    subtitle: "Copy the calculation result, cleaned link, or OCR text of the focused card. Configurable in Snippets & Shortcuts settings."
                ) {
                    let bindings = ShortcutRegistry.shared.bindings(for: .copySmartText)
                    if bindings.isEmpty {
                        Text("Off").foregroundStyle(.secondary).font(.callout)
                    } else {
                        HStack(spacing: 4) {
                            ForEach(bindings, id: \.self) {
                                ShortcutChip(text: $0.display(), height: HotkeyChipPresentation.compactHeight)
                            }
                        }
                    }
                }
            }
        }
    }
}
