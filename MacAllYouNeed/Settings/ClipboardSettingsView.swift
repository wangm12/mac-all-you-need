import AppKit
import Core
import CoreFoundation
import FeatureCore
import SwiftUI

enum ClipboardDockHeightSetting {
    static let key = "dock.height"
    static let defaultValue = 360.0
    static let range = 300.0 ... 500.0

    static func load(from defaults: UserDefaults = AppGroupSettings.defaults) -> Double {
        normalized(defaults.double(forKey: key))
    }

    static func save(_ value: Double, to defaults: UserDefaults = AppGroupSettings.defaults) {
        defaults.set(normalized(value), forKey: key)
    }

    static func normalized(_ value: Double) -> Double {
        if value == 0 { return defaultValue }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

enum ClipboardDockOpenFocusSetting {
    static let key = "dock.preserveFocusOnOpen"
    static let defaultValue = false

    static func load(from defaults: UserDefaults = AppGroupSettings.defaults) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultValue
    }
}

struct ClipboardSettingsView: View {
    let controller: AppController
    @AppStorage("retention.maxAgeDays", store: AppGroupSettings.defaults) private var maxAgeDays = 30
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
                    title: "History window",
                    subtitle: "Only browse items newer than this in the main Clipboard page."
                ) {
                    MAYNDropdown(
                        selection: $maxAgeDays,
                        options: [0, 7, 30, 90, 365],
                        title: clipboardHistoryMaxAgeTitle,
                        width: MAYNControlMetrics.widePickerWidth
                    )
                }
            }

            MAYNSection(title: "Capture") {
                BundleIDExclusionEditor(bundleIDs: $blockedApps) { ExcludedAppsStore.save($0) }
            }

            MAYNSection(title: "Auto-paste") {
                MAYNSettingsRow(
                    title: "When picking an item",
                    subtitle: "Choose whether the clipboard dock inserts into the focused app or only copies."
                ) {
                    MAYNDropdown(
                        selection: $pasteBehavior,
                        options: pasteBehaviorOptions,
                        title: pasteBehaviorTitle,
                        width: MAYNControlMetrics.widePickerWidth
                    )
                }

                if pasteBehavior == "copyThenPaste" {
                    MAYNDivider()
                    MAYNSettingsRow(
                        title: "Paste delay",
                        subtitle: "Wait after copying before sending Command-V."
                    ) {
                        MAYNNumericStepper(
                            text: "\(pasteDelay) ms",
                            value: $pasteDelay,
                            range: 50...2000,
                            step: 50,
                            presets: [50, 100, 150, 250, 500, 1000, 2000],
                            suffix: "ms"
                        )
                    }
                }
            }

            SearchPreferencesSection()

            ClipboardDockHeightSection(controller: controller)

            SmartTextEnableSection(controller: controller)
        }
        .onChange(of: maxAgeDays) { _, _ in
            postRetentionSettingsChangedDarwin()
        }
    }

    private func clipboardHistoryMaxAgeTitle(_ days: Int) -> String {
        switch days {
        case 0:
            "Forever"
        case 1:
            "1 day"
        default:
            "\(days) days"
        }
    }

    private func postRetentionSettingsChangedDarwin() {
        let name = "com.macallyouneed.settings-changed" as CFString
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name),
            nil,
            nil,
            true
        )
    }

    private let pasteBehaviorOptions = ["pasteIntoFocused", "copyOnly", "copyThenPaste"]

    private func pasteBehaviorTitle(_ behavior: String) -> String {
        switch behavior {
        case "pasteIntoFocused":
            "Paste into focused app"
        case "copyOnly":
            "Just copy"
        case "copyThenPaste":
            "Copy, then paste"
        default:
            behavior
        }
    }
}

struct ClipboardDockHeightSection: View {
    let controller: AppController
    @State private var dockHeight = ClipboardDockHeightSetting.load()
    @State private var hostWindow: NSWindow?
    @AppStorage(ClipboardDockOpenFocusSetting.key, store: AppGroupSettings.defaults) private var preserveFocusOnOpen = ClipboardDockOpenFocusSetting.defaultValue

    var body: some View {
        MAYNSection(title: "Clipboard dock") {
            MAYNSettingsRow(
                title: "Keep focused card on open",
                subtitle: "When off, opening Clipboard History highlights the newest item."
            ) {
                Toggle("", isOn: $preserveFocusOnOpen)
                    .labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Dock height",
                subtitle: "Drag to preview the bottom clipboard surface height immediately."
            ) {
                HStack(spacing: 12) {
                    Slider(
                        value: $dockHeight,
                        in: ClipboardDockHeightSetting.range,
                        step: 10,
                        onEditingChanged: { isEditing in
                            if isEditing {
                                controller.clipboardDock.keepHeightPreviewInvokerAboveDockPanel(previewInvokerWindow)
                            }
                        }
                    )
                        .frame(width: 260)
                    Text("\(Int(dockHeight)) px")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .trailing)
                }
            }
        }
        .background(
            ClipboardDockHeightWindowReader { window in
                hostWindow = window
                controller.clipboardDock.keepHeightPreviewInvokerAboveDockPanel(window)
            }
            .frame(width: 0, height: 0)
        )
        .onChange(of: dockHeight) { _, value in
            let normalized = ClipboardDockHeightSetting.normalized(value)
            if normalized != value {
                dockHeight = normalized
            }
            ClipboardDockHeightSetting.save(normalized)
            controller.clipboardDock.previewHeight(
                CGFloat(normalized),
                keepingInvokerAbove: previewInvokerWindow
            )
        }
        .onDisappear {
            controller.clipboardDock.endHeightPreviewLayering()
        }
    }

    private var previewInvokerWindow: NSWindow? {
        hostWindow ?? NSApp.mainWindow ?? NSApp.keyWindow
    }
}

enum ClipboardDockHeightControlPresentation {
    static let usesSliderAsOnlyInput = true
    static let showsEditableValueInput = false
    static let showsReadOnlyValueLabel = true
}

private struct ClipboardDockHeightWindowReader: NSViewRepresentable {
    let onWindowChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            onWindowChange(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onWindowChange(nsView.window)
        }
    }
}

// MARK: - Smart Text enable section

/// Surfaces Clipboard Smart Text as an opt-in enhancement inside the Clipboard Settings tab.
/// Reads / writes feature enabled state via FeatureRuntime through the shared controller.
struct SmartTextEnableSection: View {
    let controller: AppController
    @State private var isEnabled: Bool = false
    @State private var statePublisher: FeatureStatePublisher

    init(controller: AppController) {
        self.controller = controller
        self._statePublisher = State(initialValue: controller.featureStatePublisher)
    }

    var body: some View {
        MAYNSection(title: "Smart Text") {
            MAYNSettingsRow(
                title: "Clipboard Smart Text",
                subtitle: "Calculations, link cleaning, type detection, OCR, and semantic search."
            ) {
                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .onChange(of: isEnabled) { _, enabled in
                        Task {
                            let transition: FeatureManager.Transition = enabled ? .enable : .disable
                            try? await controller.runtime.applyTransition(transition, for: .clipboardSmartText)
                            await statePublisher.refresh()
                        }
                    }
            }
            if isEnabled {
                MAYNDivider()
                ClipboardSmartTextSettingsSection()
            }
        }
        .onAppear {
            isEnabled = statePublisher.state(for: .clipboardSmartText).activationState == .enabled
        }
        .onChange(of: statePublisher.states) { _, _ in
            isEnabled = statePublisher.state(for: .clipboardSmartText).activationState == .enabled
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