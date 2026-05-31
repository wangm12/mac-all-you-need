import Carbon.HIToolbox
import Core
import CoreFoundation
import Platform
import SwiftUI

// Internal so ClipboardSmartTextSettingsSection can reference it in @Binding.
enum LinkModeTab: String, SegmentedTabDestination, CaseIterable {
    case off, manual, auto
    var title: String {
        switch self {
        case .off: "Off"; case .manual: "Manual"; case .auto: "Auto"
        }
    }
    var symbolName: String {
        switch self {
        case .off: "link.badge.plus"; case .manual: "hand.tap"; case .auto: "wand.and.stars"
        }
    }
}

let defaultSmartCopyDescriptor = HotkeyDescriptor(keyCode: UInt32(kVK_ANSI_C), modifiers: [.command, .shift])

// MARK: - Sheet

struct ClipboardSmartTextSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var calculation: Bool
    @State private var detection: Bool
    @State private var ocr: Bool
    @State private var sensitive: Bool
    @State private var semantic: Bool
    @State private var linkMode: LinkModeTab
    // Issue 3: toggle enables/disables the shortcut action
    @State private var copyShortcutEnabled: Bool
    // Issue 4: toggle enables/disables Option+double-click
    @State private var optionDoubleClickEnabled: Bool
    // Issue 2 fix: draft descriptor — only written to registry on Save
    @State private var smartCopyDescriptor: HotkeyDescriptor

    init() {
        _calculation             = State(initialValue: SmartTextSettings.calculationEnabled())
        _detection               = State(initialValue: SmartTextSettings.detectionEnabled())
        _ocr                     = State(initialValue: SmartTextSettings.ocrEnabled())
        _sensitive               = State(initialValue: SmartTextSettings.sensitiveEnabled())
        _semantic                = State(initialValue: SmartTextSettings.semanticEnabled())
        _linkMode                = State(initialValue: LinkModeTab(rawValue: SmartTextSettings.linkMode().rawValue) ?? .auto)
        _copyShortcutEnabled     = State(initialValue: SmartTextSettings.copyShortcutEnabled())
        _optionDoubleClickEnabled = State(initialValue: SmartTextSettings.optionDoubleClickEnabled())
        let stored = ShortcutRegistry.shared.bindings(for: .copySmartText).first
        _smartCopyDescriptor     = State(initialValue: stored ?? defaultSmartCopyDescriptor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    linkMode: $linkMode,
                    copyShortcutEnabled: $copyShortcutEnabled,
                    optionDoubleClickEnabled: $optionDoubleClickEnabled,
                    smartCopyDescriptor: $smartCopyDescriptor
                )
                .padding(24)
            }
            .scrollIndicators(.never)
        }
        .frame(width: 540, height: 560)
        .background(MAYNTheme.window)
    }

    private func save() {
        SmartTextSettings.setCalculationEnabled(calculation)
        SmartTextSettings.setDetectionEnabled(detection)
        SmartTextSettings.setOCREnabled(ocr)
        SmartTextSettings.setSensitiveEnabled(sensitive)
        SmartTextSettings.setSemanticEnabled(semantic)
        SmartTextSettings.setLinkMode(SmartTextSettings.LinkMode(rawValue: linkMode.rawValue) ?? .auto)
        SmartTextSettings.setCopyShortcutEnabled(copyShortcutEnabled)
        SmartTextSettings.setOptionDoubleClickEnabled(optionDoubleClickEnabled)
        // Issue 2 fix: only write the shortcut binding to registry on Save
        ShortcutRegistry.shared.setBindings([smartCopyDescriptor], for: .copySmartText)
        let name = "com.macallyouneed.settings-changed" as CFString
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name), nil, nil, true)
    }
}

// MARK: - Section

struct ClipboardSmartTextSettingsSection: View {
    @Binding var calculation: Bool
    @Binding var detection: Bool
    @Binding var ocr: Bool
    @Binding var sensitive: Bool
    @Binding var semantic: Bool
    @Binding var linkMode: LinkModeTab
    @Binding var copyShortcutEnabled: Bool
    @Binding var optionDoubleClickEnabled: Bool
    @Binding var smartCopyDescriptor: HotkeyDescriptor

    var body: some View {
        Group {
            MAYNSection(title: "Detection") {
                MAYNSettingsRow(title: "Inline calculation",
                    subtitle: "Show the result when a clip is a math expression.") {
                    Toggle("", isOn: $calculation).labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Smart detection",
                    subtitle: "Detect emails, links, phone numbers, colors, JWTs, and code.") {
                    Toggle("", isOn: $detection).labelsHidden()
                }
            }

            MAYNSection(title: "Links") {
                MAYNSettingsRow(title: "Link cleaner",
                    subtitle: "Strip tracking parameters (utm_, fbclid, …) from copied URLs.") {
                    FunctionSegmentedTabStrip(
                        tabs: Array(LinkModeTab.allCases),
                        selection: linkMode,
                        fillsAvailableWidth: false,
                        size: .control
                    ) { linkMode = $0 }
                }
            }

            MAYNSection(title: "Images") {
                MAYNSettingsRow(title: "Image text recognition (OCR)",
                    subtitle: "Index text inside copied images so it's searchable.") {
                    Toggle("", isOn: $ocr).labelsHidden()
                }
            }

            MAYNSection(title: "Search") {
                MAYNSettingsRow(title: "Semantic ranking",
                    subtitle: "Blend meaning-based matches into clipboard search results.") {
                    Toggle("", isOn: $semantic).labelsHidden()
                }
            }

            MAYNSection(title: "Privacy") {
                MAYNSettingsRow(title: "Sensitive content filter",
                    subtitle: "Skip capturing payment cards and clips from password managers.") {
                    Toggle("", isOn: $sensitive).labelsHidden()
                }
            }

            MAYNSection(title: "Keyboard shortcut") {
                MAYNSettingsRow(title: "Copy Smart Text",
                    subtitle: "Copy the calculation result, cleaned link, or OCR text of the focused card.") {
                    HStack(spacing: 8) {
                        HotkeyRecorderControl(
                            descriptor: $smartCopyDescriptor,
                            candidateIssueMessage: { descriptor in
                                HotkeyValidation.issue(
                                    forDockShortcut: descriptor,
                                    action: .copySmartText,
                                    index: 0,
                                    dockShortcuts: ShortcutRegistry.shared.allBindings()
                                )?.message
                            },
                            defaultDescriptor: defaultSmartCopyDescriptor,
                            recorderWidth: 112,
                            recorderHeight: HotkeyChipPresentation.displayHeight,
                            reset: { smartCopyDescriptor = defaultSmartCopyDescriptor }
                        )
                        .opacity(copyShortcutEnabled ? 1 : 0.4)
                        .allowsHitTesting(copyShortcutEnabled)
                        Toggle("", isOn: $copyShortcutEnabled).labelsHidden()
                    }
                }
            }

            // Issue 4: Option+double-click toggle
            MAYNSection(title: "Mouse shortcut") {
                MAYNSettingsRow(title: "Option + double-click",
                    subtitle: "Copies the Smart Text result when holding Option and double-clicking a card.") {
                    Toggle("", isOn: $optionDoubleClickEnabled).labelsHidden()
                }
            }
        }
    }
}
