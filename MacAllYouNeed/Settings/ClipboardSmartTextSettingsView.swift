import Core
import CoreFoundation
import SwiftUI

private enum LinkModeTab: String, SegmentedTabDestination {
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

struct ClipboardSmartTextSettingsView: View {
    var body: some View {
        MAYNSettingsPage(
            title: "Smart Text",
            subtitle: "On-device intelligence over your clipboard: calculations, link cleaning, type detection, OCR, and semantic search."
        ) {
            ClipboardSmartTextSettingsSection()
        }
    }
}

struct ClipboardSmartTextSettingsSection: View {
    @State private var calculation = SmartTextSettings.calculationEnabled()
    @State private var detection = SmartTextSettings.detectionEnabled()
    @State private var ocr = SmartTextSettings.ocrEnabled()
    @State private var sensitive = SmartTextSettings.sensitiveEnabled()
    @State private var semantic = SmartTextSettings.semanticEnabled()
    @State private var linkMode = LinkModeTab(rawValue: SmartTextSettings.linkMode().rawValue) ?? .auto

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
                    ) { mode in
                        linkMode = mode
                    }
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
        }
        .onChange(of: calculation) { _, value in SmartTextSettings.setCalculationEnabled(value); notify() }
        .onChange(of: detection) { _, value in SmartTextSettings.setDetectionEnabled(value); notify() }
        .onChange(of: ocr) { _, value in SmartTextSettings.setOCREnabled(value); notify() }
        .onChange(of: sensitive) { _, value in SmartTextSettings.setSensitiveEnabled(value); notify() }
        .onChange(of: semantic) { _, value in SmartTextSettings.setSemanticEnabled(value); notify() }
        .onChange(of: linkMode) { _, value in
            SmartTextSettings.setLinkMode(SmartTextSettings.LinkMode(rawValue: value.rawValue) ?? .auto)
            notify()
        }
    }

    /// Notify the daemon (which reads these on the capture hot path) to reload.
    private func notify() {
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
