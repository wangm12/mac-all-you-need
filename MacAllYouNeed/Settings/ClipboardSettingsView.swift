import AppKit
import Core
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
                    MAYNNumericStepper(
                        text: "\(maxItems)",
                        value: $maxItems,
                        range: 100...100_000,
                        step: 100,
                        presets: [1_000, 5_000, 10_000, 50_000, 100_000]
                    )
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
        }
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

    var body: some View {
        MAYNSection(title: "Clipboard dock") {
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

enum ExcludedAppsStore {
    private static let key = "clipboardExcludedBundleIDs"
    static func load() -> [String] {
        AppGroupSettings.defaults.stringArray(forKey: key) ?? []
    }
    static func save(_ ids: [String]) {
        AppGroupSettings.defaults.set(SettingsExclusionList.normalizedBundleIDs(ids), forKey: key)
    }
}
