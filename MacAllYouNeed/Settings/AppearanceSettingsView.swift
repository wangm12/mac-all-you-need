import Core
import CoreFoundation
import SwiftUI

struct AppearanceSettingsView: View {
    let controller: AppController

    @State private var menuSymbol: String = AppGroupSettings.defaults.string(forKey: "appearance.menuSymbol") ?? "tray.full"
    @State private var dockHeight: Double = {
        let value = AppGroupSettings.defaults.double(forKey: "dock.height")
        return value == 0 ? 360 : value
    }()
    @State private var captureSound: Bool = AppGroupSettings.defaults.object(forKey: "capture.sound") as? Bool ?? false
    @State private var pasteBehavior: String = AppGroupSettings.defaults.string(forKey: "autoPaste.behavior") ?? "pasteIntoFocused"
    @State private var pasteDelay: Int = {
        let value = AppGroupSettings.defaults.integer(forKey: "autoPaste.delayMs")
        return value == 0 ? 150 : value
    }()

    private let symbols = ["tray.full", "doc.on.clipboard", "clipboard", "square.on.square", "tray"]
    private let pasteBehaviorOptions = ["pasteIntoFocused", "copyOnly", "copyThenPaste"]

    var body: some View {
        Form {
            Section("Menu bar") {
                HStack {
                    Text("Icon")
                    Spacer()
                    MAYNDropdown(
                        selection: $menuSymbol,
                        options: symbols,
                        title: menuSymbolTitle
                    )
                }
            }

            Section("Dock") {
                Slider(value: $dockHeight, in: 300...500, step: 10) {
                    Text("Height")
                } minimumValueLabel: {
                    Text("300")
                } maximumValueLabel: {
                    Text("500")
                }
                Text("Height: \(Int(dockHeight))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Capture") {
                Toggle("Play sound on capture", isOn: $captureSound)
            }

            Section("Auto-paste") {
                HStack {
                    Text("On pick")
                    Spacer()
                    MAYNDropdown(
                        selection: $pasteBehavior,
                        options: pasteBehaviorOptions,
                        title: pasteBehaviorTitle,
                        width: MAYNControlMetrics.widePickerWidth
                    )
                }

                if pasteBehavior == "copyThenPaste" {
                    HStack {
                        Text("Delay")
                        Spacer()
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
        }
        .padding()
        .onChange(of: menuSymbol) { _, value in
            AppGroupSettings.defaults.set(value, forKey: "appearance.menuSymbol")
            postSettingsChangedDarwin()
        }
        .onChange(of: dockHeight) { _, value in
            AppGroupSettings.defaults.set(value, forKey: "dock.height")
            controller.clipboardDock.dockHeight = CGFloat(value)
            postSettingsChangedDarwin()
        }
        .onChange(of: captureSound) { _, value in
            AppGroupSettings.defaults.set(value, forKey: "capture.sound")
            postSettingsChangedDarwin()
        }
        .onChange(of: pasteBehavior) { _, value in
            AppGroupSettings.defaults.set(value, forKey: "autoPaste.behavior")
            postSettingsChangedDarwin()
        }
        .onChange(of: pasteDelay) { _, value in
            AppGroupSettings.defaults.set(value, forKey: "autoPaste.delayMs")
            postSettingsChangedDarwin()
        }
    }

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

    private func menuSymbolTitle(_ symbol: String) -> String {
        switch symbol {
        case "tray.full":
            "Tray full"
        case "doc.on.clipboard":
            "Clipboard doc"
        case "clipboard":
            "Clipboard"
        case "square.on.square":
            "Stack"
        case "tray":
            "Tray"
        default:
            symbol
        }
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
